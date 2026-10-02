from decimal import Decimal

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import Payment, Sale
from app.repositories.base import PageResult, apply_sort, date_range_filter, paginate
from app.schemas.payment import PaymentFilters

SORT_FIELDS = {"created_at": Payment.created_at, "amount": Payment.amount}


def total_paid(db: Session, sale_id: int) -> Decimal:
    """Somme des paiements d'une vente, relue en base (valeur à jour, même juste après un verrou)."""
    stmt = select(func.coalesce(func.sum(Payment.amount), 0)).where(Payment.sale_id == sale_id)
    return Decimal(db.scalar(stmt) or 0)


def list_for_sale(db: Session, sale_id: int) -> list[Payment]:
    return list(db.scalars(select(Payment).where(Payment.sale_id == sale_id).order_by(Payment.id)))


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
    return paginate(db, stmt, filters.page, filters.page_size)
