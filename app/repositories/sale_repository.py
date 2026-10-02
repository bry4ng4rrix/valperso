from sqlalchemy import ColumnElement, func, select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models import Customer, Sale, invoice_number_sequence
from app.models.enums import SaleStatus
from app.repositories.base import PageResult, apply_sort, date_range_filter, paginate, search_filter
from app.schemas.common import Pagination
from app.schemas.sale import SaleHistoryFilters

SORT_FIELDS = {"created_at": Sale.created_at, "total": Sale.total, "sale_number": Sale.sale_number}


def next_invoice_number(db: Session) -> str:
    """Numéro de facture unique de la forme FAC-2026-000125 (année locale + compteur PostgreSQL)."""
    local_year = func.to_char(func.timezone(settings.TIMEZONE, func.now()), "YYYY")
    counter, year = db.execute(select(invoice_number_sequence.next_value(), local_year)).one()
    return f"FAC-{year}-{counter:06d}"


def debt_condition() -> ColumnElement[bool]:
    """Vente avec dette : non annulée et reste à payer > 0."""
    return (Sale.status != SaleStatus.CANCELLED) & (Sale.remaining_amount > 0)


def get_for_update(db: Session, sale_id: int) -> Sale | None:
    stmt = select(Sale).where(Sale.id == sale_id).with_for_update(of=Sale)
    return db.scalar(stmt.execution_options(populate_existing=True))


def list_history(db: Session, filters: SaleHistoryFilters) -> PageResult[Sale]:
    stmt = select(Sale).join(Sale.customer)
    if filters.store_id is not None:
        stmt = stmt.where(Sale.store_id == filters.store_id)
    if filters.user_id is not None:
        stmt = stmt.where(Sale.user_id == filters.user_id)
    if filters.customer_id is not None:
        stmt = stmt.where(Sale.customer_id == filters.customer_id)
    if filters.payment_status is not None:
        stmt = stmt.where(Sale.payment_status == filters.payment_status)
    if filters.status is not None:
        stmt = stmt.where(Sale.status == filters.status)
    if filters.has_debt is not None:
        stmt = stmt.where(debt_condition() if filters.has_debt else ~debt_condition())
    if filters.search:
        stmt = stmt.where(
            search_filter(
                filters.search, Sale.sale_number, Customer.first_name, Customer.last_name, Customer.phone
            )
        )
    stmt = stmt.where(*date_range_filter(Sale.created_at, filters.date_from, filters.date_to))
    stmt = apply_sort(stmt, filters.sort, SORT_FIELDS, "-created_at", Sale.id)
    return paginate(db, stmt, filters.page, filters.page_size)


def list_customer_sales(
    db: Session, customer_id: int, store_id: int | None, pagination: Pagination
) -> PageResult[Sale]:
    stmt = select(Sale).where(Sale.customer_id == customer_id)
    if store_id is not None:
        stmt = stmt.where(Sale.store_id == store_id)
    stmt = stmt.order_by(Sale.created_at.desc(), Sale.id.desc())
    return paginate(db, stmt, pagination.page, pagination.page_size)


def list_customer_debts(db: Session, customer_id: int, store_id: int | None) -> list[Sale]:
    """Ventes non soldées du client, les échéances les plus proches d'abord."""
    stmt = select(Sale).where(Sale.customer_id == customer_id, debt_condition())
    if store_id is not None:
        stmt = stmt.where(Sale.store_id == store_id)
    stmt = stmt.order_by(Sale.payment_due_date.asc().nulls_last(), Sale.created_at)
    return list(db.scalars(stmt))
