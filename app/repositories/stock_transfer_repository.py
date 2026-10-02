from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models import StockTransfer, StockTransferItem, transfer_number_sequence
from app.repositories.base import PageResult, apply_sort, date_range_filter, paginate
from app.schemas.stock_transfer import StockTransferFilters

SORT_FIELDS = {"created_at": StockTransfer.created_at, "reference": StockTransfer.reference}


def next_reference(db: Session) -> str:
    """Référence unique de la forme TRF-2026-000001 (année locale + compteur PostgreSQL)."""
    local_year = func.to_char(func.timezone(settings.TIMEZONE, func.now()), "YYYY")
    counter, year = db.execute(select(transfer_number_sequence.next_value(), local_year)).one()
    return f"TRF-{year}-{counter:06d}"


def get_for_update(db: Session, transfer_id: int) -> StockTransfer | None:
    stmt = select(StockTransfer).where(StockTransfer.id == transfer_id).with_for_update()
    return db.scalar(stmt.execution_options(populate_existing=True))


def list_transfers(db: Session, filters: StockTransferFilters) -> PageResult[StockTransfer]:
    stmt = select(StockTransfer)
    if filters.store_id is not None:
        stmt = stmt.where(
            or_(
                StockTransfer.source_store_id == filters.store_id,
                StockTransfer.destination_store_id == filters.store_id,
            )
        )
    if filters.source_store_id is not None:
        stmt = stmt.where(StockTransfer.source_store_id == filters.source_store_id)
    if filters.destination_store_id is not None:
        stmt = stmt.where(StockTransfer.destination_store_id == filters.destination_store_id)
    if filters.status is not None:
        stmt = stmt.where(StockTransfer.status == filters.status)
    if filters.product_id is not None:
        stmt = stmt.where(StockTransfer.items.any(StockTransferItem.product_id == filters.product_id))
    stmt = stmt.where(*date_range_filter(StockTransfer.created_at, filters.date_from, filters.date_to))
    stmt = apply_sort(stmt, filters.sort, SORT_FIELDS, "-created_at", StockTransfer.id)
    return paginate(db, stmt, filters.page, filters.page_size)
