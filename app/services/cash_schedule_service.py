"""Ouverture et fermeture automatiques des caisses.

Chaque jour, à l'heure de CASH_SCHEDULE_TIMEZONE (Madagascar par défaut) :

- à CASH_AUTO_OPEN_TIME (06:00), une caisse est ouverte dans chaque magasin actif qui n'en a pas.
  Le fond de caisse reprend le montant de la dernière clôture du magasin (l'argent resté dans le
  tiroir), ou 0. Si une caisse a déjà été ouverte puis clôturée à la main depuis 06:00, elle n'est
  pas rouverte : la décision de l'utilisateur est respectée jusqu'au lendemain ;
- à CASH_AUTO_CLOSE_TIME (19:00), toute caisse ouverte avant cette heure est clôturée. Personne
  ne compte l'argent : le montant compté est le montant théorique (écart 0). Pour enregistrer un
  écart réel, il faut clôturer la caisse à la main avant 19:00.

Le traitement est idempotent : il peut être lancé toutes les minutes, et rattrape un passage
manqué (serveur arrêté à 06:00 ou à 19:00). Un verrou PostgreSQL évite qu'il s'exécute deux fois
en même temps si plusieurs instances de l'API tournent.
"""

import logging
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from zoneinfo import ZoneInfo

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models import CashRegister, Store
from app.models.enums import CashRegisterStatus
from app.schemas.cash import CashRegisterRead, CashScheduleRead
from app.services import audit_service

logger = logging.getLogger(__name__)

# Identifiant arbitraire du verrou consultatif PostgreSQL de ce traitement.
ADVISORY_LOCK_KEY = 72_610_601


@dataclass
class ScheduleResult:
    opened: list[int] = field(default_factory=list)  # identifiants des magasins
    closed: list[int] = field(default_factory=list)  # identifiants des caisses


def schedule() -> CashScheduleRead:
    return CashScheduleRead(
        enabled=settings.CASH_AUTO_SCHEDULE,
        open_time=settings.CASH_AUTO_OPEN_TIME.strftime("%H:%M"),
        close_time=settings.CASH_AUTO_CLOSE_TIME.strftime("%H:%M"),
        timezone=settings.CASH_SCHEDULE_TIMEZONE,
    )


def last_boundaries(now: datetime) -> tuple[datetime, datetime]:
    """Dernière heure d'ouverture et dernière heure de fermeture passées (avec fuseau horaire)."""
    zone = ZoneInfo(settings.CASH_SCHEDULE_TIMEZONE)
    local = now.astimezone(zone)
    open_today = datetime.combine(local.date(), settings.CASH_AUTO_OPEN_TIME, tzinfo=zone)
    close_today = datetime.combine(local.date(), settings.CASH_AUTO_CLOSE_TIME, tzinfo=zone)
    last_open = open_today if local >= open_today else open_today - timedelta(days=1)
    last_close = close_today if local >= close_today else close_today - timedelta(days=1)
    return last_open, last_close


def run(db: Session, now: datetime | None = None) -> ScheduleResult:
    """Ouvre et ferme les caisses selon l'heure [now] (heure actuelle par défaut)."""
    now = now or datetime.now(UTC)
    result = ScheduleResult()
    if not db.scalar(select(func.pg_try_advisory_xact_lock(ADVISORY_LOCK_KEY))):
        return result  # une autre instance s'en occupe

    last_open, last_close = last_boundaries(now)
    _close_due_registers(db, now, last_close, result)
    # Pendant les heures d'ouverture (la dernière ouverture est plus récente que la dernière fermeture).
    if last_open > last_close:
        _open_missing_registers(db, now, last_open, result)
    db.commit()
    if result.opened or result.closed:
        logger.info(
            "Caisses automatiques : %d ouverte(s), %d clôturée(s)", len(result.opened), len(result.closed)
        )
    return result


def _close_due_registers(db: Session, now: datetime, last_close: datetime, result: ScheduleResult) -> None:
    """Clôture les caisses encore ouvertes qui ont été ouvertes avant la dernière heure de fermeture."""
    registers = db.scalars(
        select(CashRegister)
        .where(CashRegister.status == CashRegisterStatus.OPEN, CashRegister.opened_at < last_close)
        .order_by(CashRegister.id)
        .with_for_update()
        .execution_options(populate_existing=True)
    ).all()
    for register in registers:
        old_data = audit_service.snapshot(CashRegisterRead, register)
        register.closing_amount = register.expected_amount
        register.difference = Decimal("0")
        register.status = CashRegisterStatus.CLOSED
        register.closed_by = None
        register.closed_automatically = True
        register.closed_at = now
        db.flush()
        audit_service.record(
            db,
            user_id=None,
            action="cash.auto_close",
            entity_type="cash_register",
            entity_id=register.id,
            old_data=old_data,
            new_data=audit_service.snapshot(CashRegisterRead, register),
        )
        result.closed.append(register.id)


def _open_missing_registers(db: Session, now: datetime, last_open: datetime, result: ScheduleResult) -> None:
    """Ouvre une caisse dans chaque magasin actif qui n'en a pas eu depuis l'heure d'ouverture."""
    stores = db.scalars(select(Store).where(Store.is_active.is_(True)).order_by(Store.id)).all()
    for store in stores:
        already_today = db.scalar(
            select(func.count())
            .select_from(CashRegister)
            .where(
                CashRegister.store_id == store.id,
                (CashRegister.status == CashRegisterStatus.OPEN) | (CashRegister.opened_at >= last_open),
            )
        )
        if already_today:
            continue
        opening_amount = _last_closing_amount(db, store.id)
        try:
            # Point de sauvegarde : une ouverture manuelle simultanée ne bloque pas les autres magasins.
            with db.begin_nested():
                register = CashRegister(
                    store_id=store.id,
                    opened_by=None,
                    opened_automatically=True,
                    opening_amount=opening_amount,
                    expected_amount=opening_amount,
                    status=CashRegisterStatus.OPEN,
                    opened_at=now,
                )
                db.add(register)
                db.flush()
                audit_service.record(
                    db,
                    user_id=None,
                    action="cash.auto_open",
                    entity_type="cash_register",
                    entity_id=register.id,
                    new_data=audit_service.snapshot(CashRegisterRead, register),
                )
        except IntegrityError:
            logger.info("Caisse du magasin %s ouverte entre-temps : ouverture automatique ignorée", store.id)
            continue
        result.opened.append(store.id)


def _last_closing_amount(db: Session, store_id: int) -> Decimal:
    """Montant compté à la dernière clôture du magasin : l'argent resté dans la caisse."""
    amount = db.scalar(
        select(CashRegister.closing_amount)
        .where(CashRegister.store_id == store_id, CashRegister.status == CashRegisterStatus.CLOSED)
        .order_by(CashRegister.closed_at.desc(), CashRegister.id.desc())
        .limit(1)
    )
    return amount if amount is not None else Decimal("0")
