"""Statistiques calculées à la demande à partir des ventes et des stocks (aucune table dédiée)."""

from sqlalchemy.orm import Session

from app.core.config import settings
from app.models import StoreStock, User
from app.repositories import dashboard_repository, stock_repository
from app.repositories.base import PageResult
from app.schemas.dashboard import (
    DashboardQuery,
    DashboardSummary,
    LowStockQuery,
    SalesStatPoint,
    SalesStatsQuery,
    TopProduct,
    TopProductsQuery,
)
from app.schemas.sale import SaleSummary
from app.services import store_access

SUMMARY_TOP_PRODUCTS = 5
SUMMARY_RECENT_SALES = 5


def get_top_products(db: Session, user: User, query: TopProductsQuery) -> list[TopProduct]:
    store_id = store_access.visible_store_id(user, query.store_id)
    rows = dashboard_repository.top_products(db, store_id, query.date_from, query.date_to, query.limit)
    return [TopProduct.model_validate(row, from_attributes=True) for row in rows]


def get_summary(db: Session, user: User, query: DashboardQuery) -> DashboardSummary:
    store_id = store_access.visible_store_id(user, query.store_id)
    period = (store_id, query.date_from, query.date_to)

    sales_count, revenue = dashboard_repository.sales_totals(db, *period)
    cost = dashboard_repository.cost_of_goods_sold(db, *period)
    top_query = TopProductsQuery(
        store_id=store_id, date_from=query.date_from, date_to=query.date_to, limit=SUMMARY_TOP_PRODUCTS
    )
    recent_sales = dashboard_repository.recent_sales(db, *period, limit=SUMMARY_RECENT_SALES)

    return DashboardSummary(
        sales_count=sales_count,
        revenue=revenue,
        estimated_profit=revenue - cost,
        products_count=dashboard_repository.count_active_products(db),
        low_stock_count=stock_repository.count_low_stock(db, store_id, settings.LOW_STOCK_THRESHOLD),
        top_products=get_top_products(db, user, top_query),
        recent_sales=[SaleSummary.model_validate(sale) for sale in recent_sales],
    )


def get_sales_stats(db: Session, user: User, query: SalesStatsQuery) -> list[SalesStatPoint]:
    store_id = store_access.visible_store_id(user, query.store_id)
    rows = dashboard_repository.sales_by_period(db, store_id, query.date_from, query.date_to, query.group_by)
    return [SalesStatPoint.model_validate(row, from_attributes=True) for row in rows]


def get_low_stock(db: Session, user: User, query: LowStockQuery) -> PageResult[StoreStock]:
    """Articles de magasin en stock faible ou en rupture, les plus critiques d'abord."""
    store_id = store_access.visible_store_id(user, query.store_id)
    threshold = query.threshold if query.threshold is not None else settings.LOW_STOCK_THRESHOLD
    return stock_repository.list_low_stock(db, store_id, threshold, query.page, query.size)
