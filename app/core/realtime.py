"""Temps réel : chaque modification validée en base est annoncée aux applications connectées (WebSocket).

1. Pendant une transaction, les objets créés, modifiés ou supprimés sont relevés à chaque flush
   (événements SQLAlchemy) : les services n'ont rien à appeler, toute nouvelle opération est couverte.
2. Au COMMIT, ces changements partent vers le hub ; après un ROLLBACK, ils sont oubliés.
3. Le hub transmet à chaque connexion uniquement ce que son utilisateur peut voir : isolation des
   magasins, messages réservés aux membres de la conversation, journal d'audit réservé aux ADMIN.

Un message ne contient que le type et l'identifiant de ce qui a changé : l'application recharge
ensuite les données par l'API REST, qui applique les permissions habituelles.

Limite : un seul processus (uvicorn sans --workers). Avec plusieurs processus, il faudrait un canal
commun entre eux (PostgreSQL LISTEN/NOTIFY ou Redis).
"""

import asyncio
import logging
from collections.abc import Iterable
from dataclasses import dataclass, field, replace
from typing import Any

import sqlalchemy as sa
from sqlalchemy import event, inspect
from sqlalchemy.orm import Session, SessionTransaction

from app.models import (
    AuditLog,
    Category,
    CompanyInformation,
    Conversation,
    ConversationMember,
    Customer,
    Message,
    Payment,
    Product,
    ProductImage,
    Role,
    Sale,
    SaleInstallment,
    Stock,
    StockMovement,
    StockTransfer,
    Store,
    User,
)

logger = logging.getLogger(__name__)

# Utilisateur à l'origine des modifications de la session (renseigné par get_current_user).
ACTOR_KEY = "realtime_actor_id"
_PENDING_KEY = "realtime_changes"

# Messages en attente par connexion : au-delà, la connexion est fermée et l'application se resynchronise.
QUEUE_SIZE = 200


@dataclass(frozen=True)
class Audience:
    """Utilisateurs autorisés à recevoir un changement."""

    everyone: bool = False
    admins: bool = False
    store_ids: frozenset[int] = frozenset()
    user_ids: frozenset[int] = frozenset()

    def allows(self, subscriber: "Subscriber") -> bool:
        return (
            self.everyone
            or (self.admins and subscriber.is_admin)
            or (subscriber.store_id is not None and subscriber.store_id in self.store_ids)
            or subscriber.user_id in self.user_ids
        )


EVERYONE = Audience(everyone=True)
ADMINS = Audience(admins=True)


def _stores(*store_ids: int | None) -> Audience:
    """Les ADMIN et les vendeurs des magasins concernés."""
    return Audience(admins=True, store_ids=frozenset(i for i in store_ids if i is not None))


@dataclass(frozen=True)
class Change:
    """Ce qui a changé : `entity` (sale, product, stock...), `action` (created, updated, deleted), `id`."""

    entity: str
    action: str
    id: int | None
    audience: Audience = field(compare=False)
    label: str | None = field(default=None, compare=False)
    actor_id: int | None = field(default=None, compare=False)

    def to_message(self) -> dict[str, Any]:
        message: dict[str, Any] = {
            "entity": self.entity,
            "action": self.action,
            "id": self.id,
            "actor_id": self.actor_id,
        }
        if self.label:
            message["label"] = self.label
        return message


# --- Connexions -------------------------------------------------------------------------------

RECONNECT = object()
"""Demande à la connexion de se fermer : l'application se reconnecte et recharge ses écrans."""


@dataclass(eq=False)
class Subscriber:
    """Une connexion WebSocket et ce que son utilisateur a le droit de voir (lu à la connexion)."""

    user_id: int
    store_id: int | None
    is_admin: bool
    queue: asyncio.Queue[Any] = field(default_factory=lambda: asyncio.Queue(maxsize=QUEUE_SIZE))

    def push(self, message: Any) -> None:
        try:
            self.queue.put_nowait(message)
        except asyncio.QueueFull:
            # Application trop lente ou injoignable : elle rechargera tout en se reconnectant.
            logger.warning("Connexion temps réel saturée (utilisateur %s) : resynchronisation", self.user_id)
            while not self.queue.empty():
                self.queue.get_nowait()
            self.queue.put_nowait(RECONNECT)

    def reconnect(self) -> None:
        """Fermeture après les messages déjà en attente."""
        self.push(RECONNECT)


class RealtimeHub:
    """Connexions ouvertes et diffusion des changements.

    `publish` est appelé depuis les threads des requêtes (routes synchrones) : la diffusion est
    confiée à la boucle asyncio qui gère les WebSockets.
    """

    def __init__(self) -> None:
        self._loop: asyncio.AbstractEventLoop | None = None
        self._subscribers: set[Subscriber] = set()

    def subscribe(self, subscriber: Subscriber) -> None:
        self._loop = asyncio.get_running_loop()
        self._subscribers.add(subscriber)

    def unsubscribe(self, subscriber: Subscriber) -> None:
        self._subscribers.discard(subscriber)

    def publish(self, changes: list[Change]) -> None:
        loop = self._loop
        if not changes or loop is None or loop.is_closed():
            return
        try:
            loop.call_soon_threadsafe(self._dispatch, changes)
        except RuntimeError:  # boucle arrêtée entre-temps (fin du serveur ou des tests)
            pass

    def _dispatch(self, changes: list[Change]) -> None:
        for subscriber in list(self._subscribers):
            visible = [change.to_message() for change in changes if change.audience.allows(subscriber)]
            if visible:
                subscriber.push({"type": "changes", "changes": visible})
            # Rôle, magasin ou mot de passe modifié : la connexion est rouverte avec les nouveaux droits.
            if any(change.entity == "user" and change.id == subscriber.user_id for change in changes):
                subscriber.reconnect()


hub = RealtimeHub()


# --- Relevé des modifications -----------------------------------------------------------------


def _soft_delete(obj: Any, action: str) -> str:
    """Les suppressions de l'application sont des désactivations (is_active = False)."""
    if action == "updated":
        history = inspect(obj).attrs.is_active.history
        if history.deleted and history.deleted[0] is True and obj.is_active is False:
            return "deleted"
    return action


def _sale_store_id(session: Session, sale_id: int) -> int | None:
    return session.connection().scalar(sa.select(Sale.store_id).where(Sale.id == sale_id))


def _members(session: Session, conversation_id: int, *extra_user_ids: int) -> Audience:
    member_ids = session.connection().scalars(
        sa.select(ConversationMember.user_id).where(ConversationMember.conversation_id == conversation_id)
    )
    return Audience(user_ids=frozenset([*member_ids, *extra_user_ids]))


def _describe(session: Session, obj: Any, action: str) -> list[Change]:
    """Changements à annoncer pour un objet modifié (aucun pour les détails internes)."""
    match obj:
        case Product():
            return [Change("product", _soft_delete(obj, action), obj.id, EVERYONE, label=obj.name)]
        case ProductImage():
            return [Change("product", "updated", obj.product_id, EVERYONE)]
        case Category():
            return [Change("category", _soft_delete(obj, action), obj.id, EVERYONE)]
        case Customer():
            return [Change("customer", action, obj.id, EVERYONE)]
        case Store():
            return [Change("store", _soft_delete(obj, action), obj.id, EVERYONE)]
        case CompanyInformation():
            return [Change("company", action, obj.id, EVERYONE)]
        case Role():
            return [Change("role", action, obj.id, EVERYONE)]
        case Stock():
            # Identifiant : le produit dont le stock a changé dans ce magasin.
            return [Change("stock", action, obj.product_id, _stores(obj.store_id))]
        case StockMovement():
            return [Change("movement", action, obj.id, _stores(obj.store_id))]
        case StockTransfer():
            return [
                Change("transfer", action, obj.id, _stores(obj.source_store_id, obj.destination_store_id))
            ]
        case Sale():
            return [Change("sale", action, obj.id, _stores(obj.store_id), label=obj.sale_number)]
        case Payment():
            audience = _stores(_sale_store_id(session, obj.sale_id))
            return [
                Change("payment", action, obj.id, audience),
                Change("sale", "updated", obj.sale_id, audience),
            ]
        case SaleInstallment():
            return [Change("sale", "updated", obj.sale_id, _stores(_sale_store_id(session, obj.sale_id)))]
        case User():
            audience = Audience(admins=True, user_ids=frozenset({obj.id}))
            return [Change("user", _soft_delete(obj, action), obj.id, audience)]
        case AuditLog():
            return [Change("audit", action, obj.id, ADMINS)]
        case Message():
            # Identifiant : la conversation à recharger.
            return [Change("message", action, obj.conversation_id, _members(session, obj.conversation_id))]
        case Conversation():
            return [Change("conversation", action, obj.id, _members(session, obj.id))]
        case ConversationMember():
            if action == "updated":  # lecture des messages : seul ce membre est concerné
                audience = Audience(user_ids=frozenset({obj.user_id}))
            else:  # membre ajouté ou retiré : tous les membres, et lui-même
                audience = _members(session, obj.conversation_id, obj.user_id)
            return [Change("conversation", "updated", obj.conversation_id, audience)]
    return []


def _merge(changes: Iterable[Change]) -> list[Change]:
    """Un objet créé puis modifié dans la même transaction n'est annoncé qu'une fois (créé)."""
    changes = list(changes)
    created = {(c.entity, c.id) for c in changes if c.action == "created"}
    return [c for c in changes if c.action != "updated" or (c.entity, c.id) not in created]


@event.listens_for(Session, "after_flush")
def _collect_changes(session: Session, _flush_context: Any) -> None:
    pending: dict[tuple[str, str, int | None], Change] = session.info.setdefault(_PENDING_KEY, {})
    actor_id = session.info.get(ACTOR_KEY)
    actions = (("created", session.new), ("updated", session.dirty), ("deleted", session.deleted))
    for action, objects in actions:
        for obj in objects:
            # Colonnes seulement : ajouter une vente à la liste d'un client ne modifie pas le client.
            # Les permissions d'un rôle sont une liste : elles comptent.
            with_collections = isinstance(obj, Role)
            if action == "updated" and not session.is_modified(obj, include_collections=with_collections):
                continue
            for change in _describe(session, obj, action):
                pending[(change.entity, change.action, change.id)] = replace(change, actor_id=actor_id)


@event.listens_for(Session, "after_commit")
def _publish_changes(session: Session) -> None:
    pending = session.info.pop(_PENDING_KEY, None)
    if pending:
        hub.publish(_merge(pending.values()))


@event.listens_for(Session, "after_soft_rollback")
def _forget_changes(session: Session, previous_transaction: SessionTransaction) -> None:
    if not previous_transaction.nested:
        session.info.pop(_PENDING_KEY, None)
