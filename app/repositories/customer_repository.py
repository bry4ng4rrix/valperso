from typing import Any

import sqlalchemy as sa
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import Customer, Payment, Sale
from app.models.enums import SaleStatus
from app.repositories.base import PageResult, apply_sort, paginate, paginate_rows, search_filter
from app.schemas.customer import CustomerFilters


def find_same_customer(db: Session, first_name: str, last_name: str, phone: str | None) -> Customer | None:
    """Client existant avec exactement les mêmes nom, prénom et téléphone (évite les doublons)."""
    stmt = (
        select(Customer)
        .where(
            Customer.first_name == first_name,
            Customer.last_name == last_name,
            Customer.phone.is_not_distinct_from(phone),
        )
        .order_by(Customer.id)
        .limit(1)
    )
    return db.scalar(stmt)


def _sales_summary(store_id: int | None) -> sa.Subquery:
    """Par client : nombre de ventes, montant total, montant payé et date du dernier achat
    (ventes non annulées, éventuellement limitées à un magasin)."""
    paid_per_sale = (
        select(Payment.sale_id, func.sum(Payment.amount).label("paid")).group_by(Payment.sale_id).subquery()
    )
    stmt = (
        select(
            Sale.customer_id.label("customer_id"),
            func.count(Sale.id).label("total_purchases"),
            func.sum(Sale.total).label("total_amount"),
            func.sum(func.coalesce(paid_per_sale.c.paid, 0)).label("total_paid"),
            func.max(Sale.created_at).label("last_sale_date"),
        )
        .outerjoin(paid_per_sale, paid_per_sale.c.sale_id == Sale.id)
        .where(Sale.status != SaleStatus.CANCELLED)
        .group_by(Sale.customer_id)
    )
    if store_id is not None:
        stmt = stmt.where(Sale.store_id == store_id)
    return stmt.subquery()


def _contacts_query(filters: CustomerFilters, scope_store_id: int | None) -> sa.Select[Any]:
    """Clients + totaux calculés. `scope_store_id` limite les totaux (et le filtre de dette) à un magasin."""
    summary = _sales_summary(scope_store_id)
    total_amount = func.coalesce(summary.c.total_amount, 0)
    total_paid = func.coalesce(summary.c.total_paid, 0)
    remaining = total_amount - total_paid

    stmt = select(
        Customer,
        func.coalesce(summary.c.total_purchases, 0).label("total_purchases"),
        total_amount.label("total_amount"),
        total_paid.label("total_paid"),
        remaining.label("remaining_amount"),
        summary.c.last_sale_date.label("last_sale_date"),
    ).outerjoin(summary, summary.c.customer_id == Customer.id)

    if filters.search:
        stmt = stmt.where(search_filter(filters.search, Customer.first_name, Customer.last_name, Customer.phone))
    if filters.phone:
        stmt = stmt.where(search_filter(filters.phone, Customer.phone))
    if filters.store_id is not None:
        stmt = stmt.where(summary.c.customer_id.is_not(None))  # a acheté dans ce magasin
    if filters.has_debt is not None:
        stmt = stmt.where(remaining > 0 if filters.has_debt else remaining <= 0)

    sort_fields = {
        "name": Customer.last_name,
        "created_at": Customer.created_at,
        "remaining_amount": remaining,
        "total_amount": total_amount,
        "last_sale_date": summary.c.last_sale_date,
    }
    return apply_sort(stmt, filters.sort, sort_fields, "name", Customer.id)


def list_customers(db: Session, filters: CustomerFilters, scope_store_id: int | None) -> PageResult[Customer]:
    # `paginate` ne garde que la première colonne de la requête : l'objet Customer.
    return paginate(db, _contacts_query(filters, scope_store_id), filters.page, filters.page_size)


def list_contacts(db: Session, filters: CustomerFilters, scope_store_id: int | None) -> PageResult[sa.Row[Any]]:
    return paginate_rows(db, _contacts_query(filters, scope_store_id), filters.page, filters.page_size)
