from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Payment, Sale
from app.repositories.base import PageResult, apply_sort, date_range_filter, paginate
from app.schemas.payment import PaymentFilters

SORT_FIELDS = {"created_at": Payment.created_at, "amount": Payment.amount}


def list_payments(db: Session, filters: PaymentFilters) -> PageResult[Payment]:
    stmt = select(Payment)
    if filters.store_id is not None:
        stmt = stmt.join(Payment.sale).where(Sale.store_id == filters.store_id)
    if filters.sale_id is not None:
        stmt = stmt.where(Payment.sale_id == filters.sale_id)
    if filters.method is not None:
        stmt = stmt.where(Payment.method == filters.method)
    stmt = stmt.where(*date_range_filter(Payment.created_at, filters.date_from, filters.date_to))
    stmt = apply_sort(stmt, filters.sort, SORT_FIELDS, "-created_at", Payment.id)
    return paginate(db, stmt, filters.page, filters.size)
