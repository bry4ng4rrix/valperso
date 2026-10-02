from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models import Sale, sale_number_sequence
from app.repositories.base import PageResult, apply_sort, date_range_filter, paginate, search_filter
from app.schemas.sale import SaleFilters

SORT_FIELDS = {"created_at": Sale.created_at, "total": Sale.total, "sale_number": Sale.sale_number}


def next_sale_number(db: Session) -> str:
    """Numéro unique de la forme V20261002-000123 (date locale + compteur PostgreSQL)."""
    local_day = func.to_char(func.timezone(settings.TIMEZONE, func.now()), "YYYYMMDD")
    counter, day = db.execute(select(sale_number_sequence.next_value(), local_day)).one()
    return f"V{day}-{counter:06d}"


def get_for_update(db: Session, sale_id: int) -> Sale | None:
    return db.scalar(select(Sale).where(Sale.id == sale_id).with_for_update())


def list_sales(db: Session, filters: SaleFilters) -> PageResult[Sale]:
    stmt = select(Sale)
    if filters.store_id is not None:
        stmt = stmt.where(Sale.store_id == filters.store_id)
    if filters.user_id is not None:
        stmt = stmt.where(Sale.user_id == filters.user_id)
    if filters.status is not None:
        stmt = stmt.where(Sale.status == filters.status)
    if filters.search:
        stmt = stmt.where(search_filter(filters.search, Sale.sale_number, Sale.customer_name))
    stmt = stmt.where(*date_range_filter(Sale.created_at, filters.date_from, filters.date_to))
    stmt = apply_sort(stmt, filters.sort, SORT_FIELDS, "-created_at", Sale.id)
    return paginate(db, stmt, filters.page, filters.size)
