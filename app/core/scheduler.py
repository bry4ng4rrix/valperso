"""Tâches périodiques lancées avec l'API (une boucle asyncio, sans dépendance supplémentaire)."""

import asyncio
import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager, suppress

from fastapi import FastAPI

from app.core.config import settings
from app.core.database import SessionLocal
from app.services import cash_schedule_service

logger = logging.getLogger(__name__)

# Vérification toutes les minutes : ouverture à 06:00 et fermeture à 19:00 à la minute près.
CHECK_INTERVAL_SECONDS = 60


def run_cash_schedule_once() -> None:
    with SessionLocal() as db:
        cash_schedule_service.run(db)


async def _cash_schedule_loop() -> None:
    while True:
        try:
            await asyncio.to_thread(run_cash_schedule_once)
        except Exception:  # erreur ponctuelle (base indisponible...) : la boucle continue
            logger.exception("Échec de l'ouverture / fermeture automatique des caisses")
        await asyncio.sleep(CHECK_INTERVAL_SECONDS)


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    task = asyncio.create_task(_cash_schedule_loop()) if settings.CASH_AUTO_SCHEDULE else None
    if task:
        logger.info(
            "Caisses automatiques : ouverture à %s, fermeture à %s (%s)",
            settings.CASH_AUTO_OPEN_TIME.strftime("%H:%M"),
            settings.CASH_AUTO_CLOSE_TIME.strftime("%H:%M"),
            settings.CASH_SCHEDULE_TIMEZONE,
        )
    yield
    if task:
        task.cancel()
        with suppress(asyncio.CancelledError):
            await task
