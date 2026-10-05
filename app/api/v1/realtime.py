"""WebSocket temps réel : l'application est prévenue de chaque modification qu'elle a le droit de voir.

Connexion : `ws(s)://<serveur>/api/v1/ws?token=<access_token>` (un navigateur ne peut pas envoyer
d'en-tête Authorization sur un WebSocket). Messages envoyés par le serveur (JSON) :

- `{"type": "ready"}` : connexion authentifiée, les changements suivants seront tous reçus ;
- `{"type": "changes", "changes": [{"entity": "sale", "action": "created", "id": 12,
  "actor_id": 3, "label": "FAC-2026-000012"}, ...]}` : une transaction validée ;
- `{"type": "ping"}` : toutes les 25 secondes, pour garder la connexion ouverte.

Codes de fermeture : 4401 = jeton invalide ou expiré (renouveler le jeton puis se reconnecter),
4000 = se reconnecter (droits modifiés ou trop de messages en attente : recharger les écrans).
"""

import contextlib
from collections.abc import Awaitable, Callable
from functools import partial
from typing import Any

import anyio
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from starlette.concurrency import run_in_threadpool

from app.core.dependencies import DbSession
from app.core.exceptions import AuthenticationError
from app.core.permissions import is_admin
from app.core.realtime import RECONNECT, Subscriber, hub
from app.core.security import TokenType, decode_token, ensure_token_is_current
from app.models import User

router = APIRouter(tags=["Temps réel"])

PING_INTERVAL = 25  # secondes
CLOSE_UNAUTHORIZED = 4401
CLOSE_RECONNECT = 4000


def _authenticate(db: DbSession, token: str | None) -> tuple[int, int | None, bool]:
    """Mêmes règles que les routes REST (get_current_user) ; renvoie ce que l'utilisateur peut voir."""
    try:
        if not token:
            raise AuthenticationError()
        data = decode_token(token, TokenType.ACCESS)
        user = db.get(User, data.user_id)
        if user is None or not user.is_active:
            raise AuthenticationError("Utilisateur introuvable ou désactivé")
        ensure_token_is_current(data, user.token_version)
        return user.id, user.store_id, is_admin(user)
    finally:
        # La connexion reste ouverte longtemps : la connexion PostgreSQL est rendue tout de suite.
        db.rollback()


async def _send_changes(websocket: WebSocket, subscriber: Subscriber) -> None:
    with contextlib.suppress(WebSocketDisconnect, RuntimeError):
        while True:
            message: Any = {"type": "ping"}
            with anyio.move_on_after(PING_INTERVAL):
                message = await subscriber.queue.get()
            if message is RECONNECT:
                await websocket.close(code=CLOSE_RECONNECT)
                return
            await websocket.send_json(message)


async def _wait_for_disconnect(websocket: WebSocket) -> None:
    """Les messages du client sont ignorés : seule sa déconnexion compte."""
    with contextlib.suppress(WebSocketDisconnect, RuntimeError):
        while True:
            await websocket.receive_text()


@router.websocket("/ws", name="Changements en temps réel")
async def realtime(websocket: WebSocket, db: DbSession, token: str | None = None) -> None:
    await websocket.accept()
    try:
        user_id, store_id, admin = await run_in_threadpool(_authenticate, db, token)
    except AuthenticationError as error:
        # Raison : le code de l'erreur (ASCII court, ex. TOKEN_REVOKED), lisible par l'application.
        await websocket.close(code=CLOSE_UNAUTHORIZED, reason=error.code)
        return
    subscriber = Subscriber(user_id=user_id, store_id=store_id, is_admin=admin)
    hub.subscribe(subscriber)
    try:
        await websocket.send_json({"type": "ready"})
        # Envoi des changements et attente de la déconnexion : la première qui se termine arrête l'autre.
        async with anyio.create_task_group() as tasks:

            async def until_done(job: Callable[[], Awaitable[None]]) -> None:
                await job()
                tasks.cancel_scope.cancel()

            tasks.start_soon(until_done, partial(_send_changes, websocket, subscriber))
            tasks.start_soon(until_done, partial(_wait_for_disconnect, websocket))
    finally:
        hub.unsubscribe(subscriber)
        with contextlib.suppress(RuntimeError, WebSocketDisconnect):
            await websocket.close()
