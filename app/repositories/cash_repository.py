from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import CashRegister, CashTransaction
from app.models.enums import CashRegisterStatus
from app.repositories.base import PageResult, apply_sort, date_range_filter, paginate
from app.schemas.cash import CashRegisterFilters

SORT_FIELDS = {"opened_at": CashRegister.opened_at, "closed_at": CashRegister.closed_at}


def get_open_register(db: Session, store_id: int, *, for_update: bool = False) -> CashRegister | None:
    stmt = select(CashRegister).where(
        CashRegister.store_id == store_id, CashRegister.status == CashRegisterStatus.OPEN
    )
    if for_update:
        stmt = stmt.with_for_update()
    return db.scalar(stmt)


def get_for_update(db: Session, register_id: int) -> CashRegister | None:
    return db.scalar(select(CashRegister).where(CashRegister.id == register_id).with_for_update())


def list_registers(db: Session, filters: CashRegisterFilters) -> PageResult[CashRegister]:
    stmt = select(CashRegister)
    if filters.store_id is not None:
        stmt = stmt.where(CashRegister.store_id == filters.store_id)
    if filters.status is not None:
        stmt = stmt.where(CashRegister.status == filters.status)
    stmt = stmt.where(*date_range_filter(CashRegister.opened_at, filters.date_from, filters.date_to))
    stmt = apply_sort(stmt, filters.sort, SORT_FIELDS, "-opened_at", CashRegister.id)
    return paginate(db, stmt, filters.page, filters.page_size)


def list_transactions(db: Session, register_id: int, page: int, page_size: int) -> PageResult[CashTransaction]:
    stmt = (
        select(CashTransaction)
        .where(CashTransaction.cash_register_id == register_id)
        .order_by(CashTransaction.id.desc())
    )
    return paginate(db, stmt, page, page_size)
