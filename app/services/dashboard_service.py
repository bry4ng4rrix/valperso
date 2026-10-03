"""Statistiques calculées à la demande à partir des ventes, paiements et stocks (aucune table dédiée).

Les transferts ne sont jamais comptés comme ventes, pertes ou dépenses : ils déplacent seulement
le stock entre magasins, le stock global reste identique.
"""

from decimal import Decimal

from sqlalchemy.orm import Session

from app.models import Stock, User
from app.repositories import dashboard_repository, product_repository, stock_repository, store_repository
from app.repositories.base import PageResult
from app.schemas.dashboard import (
    DashboardQuery,
    DashboardSummary,
    LeastSoldProduct,
    LowStockQuery,
    SalesStatPoint,
    SalesStatsQuery,
    StockValue,
    StockValueQuery,
    StockValueReport,
    StorePerformance,
    StoreStockValue,
    TopProduct,
    TopProductsQuery,
)
from app.schemas.sale import SaleSummary
from app.schemas.store import StoreSummary
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

    sales_count, revenue, debt_amount = dashboard_repository.sales_totals(db, *period)
    top_query = TopProductsQuery(
        store_id=store_id, date_from=query.date_from, date_to=query.date_to, limit=SUMMARY_TOP_PRODUCTS
    )
    return DashboardSummary(
        sales_count=sales_count,
        revenue=revenue,
        estimated_profit=stock_repository.potential_profit(db, store_id),
        sales_margin=dashboard_repository.sales_margin(db, *period),
        amount_collected=dashboard_repository.amount_collected(db, *period),
        debt_amount=debt_amount,
        products_count=product_repository.count_active(db),
        stores_count=store_repository.count_active(db),
        stock_quantity=stock_repository.total_quantity(db, store_id),
        low_stock_count=stock_repository.count_low_stock(db, store_id),
        out_of_stock_count=stock_repository.count_out_of_stock(db, store_id),
        unavailable_products_count=stock_repository.count_unavailable_products(db),
        top_products=get_top_products(db, user, top_query),
        least_sold_products=[
            LeastSoldProduct.model_validate(row, from_attributes=True)
            for row in dashboard_repository.least_sold_products(db, *period, limit=SUMMARY_TOP_PRODUCTS)
        ],
        stores_performance=[
            StorePerformance(
                store=StoreSummary.model_validate(row.Store),
                **{key: getattr(row, key) for key in StorePerformance.model_fields if key != "store"},
            )
            for row in dashboard_repository.stores_performance(db, *period)
        ],
        recent_sales=[
            SaleSummary.model_validate(sale)
            for sale in dashboard_repository.recent_sales(db, *period, limit=SUMMARY_RECENT_SALES)
        ],
    )


def get_sales_stats(db: Session, user: User, query: SalesStatsQuery) -> list[SalesStatPoint]:
    store_id = store_access.visible_store_id(user, query.store_id)
    rows = dashboard_repository.sales_by_period(db, store_id, query.date_from, query.date_to, query.group_by)
    return [SalesStatPoint.model_validate(row, from_attributes=True) for row in rows]


def get_low_stock(db: Session, user: User, query: LowStockQuery) -> PageResult[Stock]:
    """Lignes de stock en alerte : stock faible ou rupture, les plus critiques d'abord."""
    store_id = store_access.visible_store_id(user, query.store_id)
    alert = Stock.low_stock | Stock.out_of_stock
    return stock_repository.list_alerts(db, alert, store_id, None, query.page, query.page_size)


def _stock_value(quantity: int, purchase_value: Decimal, sale_value: Decimal) -> dict:
    return {
        "quantity": quantity,
        "purchase_value": purchase_value,
        "sale_value": sale_value,
        "potential_profit": sale_value - purchase_value,
    }


def get_stock_value(db: Session, user: User, query: StockValueQuery) -> StockValueReport:
    """Valeur du stock par magasin et globale (ou d'un seul produit) : valeur au prix de stock,
    valeur de vente potentielle et bénéfice potentiel. Un transfert ne change pas le total."""
    store_id = store_access.visible_store_id(user, query.store_id)
    rows = stock_repository.stock_value_by_store(db, store_id, query.product_id)
    stores = [
        StoreStockValue(
            store=StoreSummary.model_validate(row.Store),
            **_stock_value(row.quantity, row.purchase_value, row.sale_value),
        )
        for row in rows
    ]
    total = StockValue(
        **_stock_value(
            sum(store.quantity for store in stores),
            sum((store.purchase_value for store in stores), Decimal("0")),
            sum((store.sale_value for store in stores), Decimal("0")),
        )
    )
    return StockValueReport(stores=stores, total=total)
