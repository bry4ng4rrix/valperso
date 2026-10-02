"""Requêtes d'agrégation du tableau de bord, calculées à partir des données existantes.

Seules les ventes (non annulées) et les paiements entrent dans le chiffre d'affaires et les
encaissements : les transferts de stock n'y apparaissent jamais (ni vente, ni perte, ni dépense).
"""

from datetime import datetime
from decimal import Decimal
from typing import Any, Literal

import sqlalchemy as sa
from sqlalchemy import ColumnElement, func, select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models import Payment, Product, Sale, SaleItem
from app.models.enums import SaleStatus
from app.repositories.base import date_range_filter


def _valid_sales(
    store_id: int | None, date_from: datetime | None, date_to: datetime | None
) -> list[ColumnElement[bool]]:
    conditions = [Sale.status != SaleStatus.CANCELLED]
    if store_id is not None:
        conditions.append(Sale.store_id == store_id)
    return conditions + date_range_filter(Sale.created_at, date_from, date_to)


def sales_totals(
    db: Session, store_id: int | None, date_from: datetime | None, date_to: datetime | None
) -> tuple[int, Decimal, Decimal]:
    """Nombre de ventes, chiffre d'affaires et total des restes à payer."""
    stmt = select(
        func.count(Sale.id),
        func.coalesce(func.sum(Sale.total), 0),
        func.coalesce(func.sum(Sale.remaining_amount), 0),
    ).where(*_valid_sales(store_id, date_from, date_to))
    count, revenue, debt = db.execute(stmt).one()
    return count, Decimal(revenue), Decimal(debt)


def amount_collected(
    db: Session, store_id: int | None, date_from: datetime | None, date_to: datetime | None
) -> Decimal:
    """Encaissements : paiements reçus sur la période (date du paiement, pas de la vente)."""
    stmt = (
        select(func.coalesce(func.sum(Payment.amount), 0))
        .join(Sale, Payment.sale_id == Sale.id)
        .where(Sale.status != SaleStatus.CANCELLED)
        .where(*date_range_filter(Payment.created_at, date_from, date_to))
    )
    if store_id is not None:
        stmt = stmt.where(Sale.store_id == store_id)
    return Decimal(db.scalar(stmt) or 0)


def cost_of_goods_sold(
    db: Session, store_id: int | None, date_from: datetime | None, date_to: datetime | None
) -> Decimal:
    """Coût d'achat des articles vendus, au prix d'achat actuel des produits."""
    stmt = (
        select(func.coalesce(func.sum(SaleItem.quantity * Product.purchase_price), 0))
        .select_from(SaleItem)
        .join(Sale, SaleItem.sale_id == Sale.id)
        .join(Product, SaleItem.product_id == Product.id)
        .where(*_valid_sales(store_id, date_from, date_to))
    )
    return Decimal(db.scalar(stmt) or 0)


def top_products(
    db: Session, store_id: int | None, date_from: datetime | None, date_to: datetime | None, limit: int
) -> list[sa.Row[Any]]:
    quantity_sold = func.sum(SaleItem.quantity).label("quantity_sold")
    stmt = (
        select(
            SaleItem.product_id,
            Product.reference,
            Product.name,
            quantity_sold,
            func.sum(SaleItem.total).label("revenue"),
        )
        .join(Sale, SaleItem.sale_id == Sale.id)
        .join(Product, SaleItem.product_id == Product.id)
        .where(*_valid_sales(store_id, date_from, date_to))
        .group_by(SaleItem.product_id, Product.reference, Product.name)
        .order_by(quantity_sold.desc(), SaleItem.product_id)
        .limit(limit)
    )
    return list(db.execute(stmt))


def sales_by_period(
    db: Session,
    store_id: int | None,
    date_from: datetime | None,
    date_to: datetime | None,
    group_by: Literal["day", "month"],
) -> list[sa.Row[Any]]:
    # Les dates sont regroupées dans le fuseau horaire local (TIMEZONE) et non en UTC.
    local_time = func.timezone(settings.TIMEZONE, Sale.created_at)
    period = sa.cast(func.date_trunc(group_by, local_time), sa.Date).label("period")
    stmt = (
        select(period, func.count(Sale.id).label("sales_count"), func.sum(Sale.total).label("revenue"))
        .where(*_valid_sales(store_id, date_from, date_to))
        # Regroupement par l'alias : évite de répéter l'expression (et ses paramètres) dans le GROUP BY.
        .group_by(sa.text("period"))
        .order_by(sa.text("period"))
    )
    return list(db.execute(stmt))


def recent_sales(
    db: Session, store_id: int | None, date_from: datetime | None, date_to: datetime | None, limit: int
) -> list[Sale]:
    stmt = select(Sale).where(*date_range_filter(Sale.created_at, date_from, date_to))
    if store_id is not None:
        stmt = stmt.where(Sale.store_id == store_id)
    return list(db.scalars(stmt.order_by(Sale.created_at.desc(), Sale.id.desc()).limit(limit)))
