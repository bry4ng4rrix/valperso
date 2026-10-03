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
from app.models import Payment, Product, Sale, SaleItem, Stock, Store
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


def sales_margin(
    db: Session, store_id: int | None, date_from: datetime | None, date_to: datetime | None
) -> Decimal:
    """Marge des produits vendus : (prix de vente - prix) x quantité, aux prix enregistrés à chaque vente
    (un changement de prix ensuite ne modifie pas les ventes passées)."""
    margin = SaleItem.quantity * (SaleItem.unit_price - SaleItem.unit_purchase_price)
    stmt = (
        select(func.coalesce(func.sum(margin), 0))
        .select_from(SaleItem)
        .join(Sale, SaleItem.sale_id == Sale.id)
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


def least_sold_products(
    db: Session, store_id: int | None, date_from: datetime | None, date_to: datetime | None, limit: int
) -> list[sa.Row[Any]]:
    """Produits actifs encore en stock, les moins vendus sur la période d'abord (0 vendu compris) ;
    à égalité, ceux qui ont le plus de stock (ils dorment le plus)."""
    in_stock = select(Stock.product_id, func.sum(Stock.quantity).label("stock_quantity")).group_by(
        Stock.product_id
    )
    if store_id is not None:
        in_stock = in_stock.where(Stock.store_id == store_id)
    in_stock = in_stock.having(func.sum(Stock.quantity) > 0).subquery()
    sold = (
        select(
            SaleItem.product_id,
            func.sum(SaleItem.quantity).label("quantity"),
            func.sum(SaleItem.total).label("revenue"),
        )
        .join(Sale, SaleItem.sale_id == Sale.id)
        .where(*_valid_sales(store_id, date_from, date_to))
        .group_by(SaleItem.product_id)
        .subquery()
    )
    quantity_sold = func.coalesce(sold.c.quantity, 0).label("quantity_sold")
    stmt = (
        select(
            Product.id.label("product_id"),
            Product.reference,
            Product.name,
            quantity_sold,
            func.coalesce(sold.c.revenue, 0).label("revenue"),
            in_stock.c.stock_quantity,
        )
        .join(in_stock, in_stock.c.product_id == Product.id)
        .outerjoin(sold, sold.c.product_id == Product.id)
        .where(Product.is_active.is_(True))
        .order_by(quantity_sold, in_stock.c.stock_quantity.desc(), Product.name, Product.id)
        .limit(limit)
    )
    return list(db.execute(stmt))


def stores_performance(
    db: Session, store_id: int | None, date_from: datetime | None, date_to: datetime | None
) -> list[sa.Row[Any]]:
    """Par magasin actif : ventes, chiffre d'affaires, marge des produits vendus et reste à payer
    sur la période, et stock actuel. Les meilleurs chiffres d'affaires d'abord."""
    valid = _valid_sales(None, date_from, date_to)
    sales = (
        select(
            Sale.store_id,
            func.count(Sale.id).label("sales_count"),
            func.sum(Sale.total).label("revenue"),
            func.sum(Sale.remaining_amount).label("debt_amount"),
        )
        .where(*valid)
        .group_by(Sale.store_id)
        .subquery()
    )
    margin = (
        select(
            Sale.store_id,
            func.sum(SaleItem.quantity * (SaleItem.unit_price - SaleItem.unit_purchase_price)).label(
                "margin"
            ),
        )
        .join(Sale, SaleItem.sale_id == Sale.id)
        .where(*valid)
        .group_by(Sale.store_id)
        .subquery()
    )
    stock = (
        select(Stock.store_id, func.sum(Stock.quantity).label("quantity")).group_by(Stock.store_id).subquery()
    )
    revenue = func.coalesce(sales.c.revenue, 0).label("revenue")
    stmt = (
        select(
            Store,
            func.coalesce(sales.c.sales_count, 0).label("sales_count"),
            revenue,
            func.coalesce(margin.c.margin, 0).label("sales_margin"),
            func.coalesce(sales.c.debt_amount, 0).label("debt_amount"),
            func.coalesce(stock.c.quantity, 0).label("stock_quantity"),
        )
        .outerjoin(sales, sales.c.store_id == Store.id)
        .outerjoin(margin, margin.c.store_id == Store.id)
        .outerjoin(stock, stock.c.store_id == Store.id)
        .where(Store.is_active.is_(True))
        .order_by(revenue.desc(), Store.is_central.desc(), Store.name)
    )
    if store_id is not None:
        stmt = stmt.where(Store.id == store_id)
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
