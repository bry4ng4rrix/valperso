from collections.abc import Iterable
from decimal import Decimal
from typing import Any

import sqlalchemy as sa
from sqlalchemy import ColumnElement, and_, func, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.models import Product, Stock, StockMovement, Store
from app.repositories.base import PageResult, apply_sort, date_range_filter, paginate, search_filter
from app.schemas.stock import StockFilters, StockMovementFilters

STOCK_SORT_FIELDS = {
    "name": Product.name,
    "reference": Product.reference,
    "quantity": Stock.quantity,
    "updated_at": Stock.updated_at,
}
MOVEMENT_SORT_FIELDS = {"created_at": StockMovement.created_at, "quantity": StockMovement.quantity}

StockKey = tuple[int, int]  # (store_id, product_id)


# --- Lecture et verrouillage des lignes de stock --------------------------------------------------


def get_line(db: Session, store_id: int, product_id: int) -> Stock | None:
    return db.scalar(select(Stock).where(Stock.store_id == store_id, Stock.product_id == product_id))


def create_missing_lines(
    db: Session, store_ids: Iterable[int], product_ids: Iterable[int], alert_threshold: int
) -> None:
    """Crée à 0 les lignes de stock manquantes. Une ligne existante n'est jamais dupliquée
    (contrainte UNIQUE(product_id, store_id) + ON CONFLICT DO NOTHING), même en cas d'accès simultanés."""
    rows = [
        {"store_id": store_id, "product_id": product_id, "quantity": 0, "alert_threshold": alert_threshold}
        for store_id in sorted(set(store_ids))
        for product_id in sorted(set(product_ids))
    ]  # ordre fixe : deux transactions simultanées ne peuvent pas s'interbloquer
    if rows:
        db.execute(
            insert(Stock).values(rows).on_conflict_do_nothing(index_elements=["product_id", "store_id"])
        )


def lock_lines(db: Session, store_ids: Iterable[int], product_ids: Iterable[int]) -> dict[StockKey, Stock]:
    """Charge et verrouille (SELECT ... FOR UPDATE) les lignes de stock jusqu'au COMMIT.

    Une autre transaction qui veut modifier ces lignes attend la fin de la nôtre : deux ventes
    ou transferts simultanés ne peuvent donc pas retirer le même stock. Les lignes sont toujours
    verrouillées par id croissant, ce qui évite les interblocages (deadlocks).
    """
    stmt = (
        select(Stock)
        .where(Stock.store_id.in_(set(store_ids)), Stock.product_id.in_(set(product_ids)))
        .order_by(Stock.id)
        .with_for_update(of=Stock)
        .execution_options(populate_existing=True)
    )
    return {(line.store_id, line.product_id): line for line in db.scalars(stmt)}


# --- Listes --------------------------------------------------------------------------------------


def _stock_query(
    store_id: int | None,
    *,
    product_id: int | None = None,
    category_id: int | None = None,
    search: str | None = None,
) -> sa.Select[Any]:
    stmt = select(Stock).join(Stock.product)
    if store_id is not None:
        stmt = stmt.where(Stock.store_id == store_id)
    if product_id is not None:
        stmt = stmt.where(Stock.product_id == product_id)
    if category_id is not None:
        stmt = stmt.where(Product.category_id == category_id)
    if search:
        stmt = stmt.where(search_filter(search, Product.reference, Product.name))
    return stmt


def list_stocks(db: Session, filters: StockFilters) -> PageResult[Stock]:
    stmt = _stock_query(
        filters.store_id,
        product_id=filters.product_id,
        category_id=filters.category_id,
        search=filters.search,
    )
    if filters.low_stock is not None:
        stmt = stmt.where(Stock.low_stock if filters.low_stock else ~Stock.low_stock)
    if filters.out_of_stock is not None:
        stmt = stmt.where(Stock.out_of_stock if filters.out_of_stock else ~Stock.out_of_stock)
    stmt = apply_sort(stmt, filters.sort, STOCK_SORT_FIELDS, "name", Stock.id)
    return paginate(db, stmt, filters.page, filters.page_size)


def list_alerts(
    db: Session,
    condition: ColumnElement[bool],
    store_id: int | None,
    search: str | None,
    page: int,
    page_size: int,
) -> PageResult[Stock]:
    """Lignes de stock en alerte (faible ou rupture) de produits actifs, les plus critiques d'abord."""
    stmt = (
        _stock_query(store_id, search=search)
        .where(condition, Product.is_active.is_(True))
        .order_by(Stock.quantity, Product.name, Stock.id)
    )
    return paginate(db, stmt, page, page_size)


# --- Indicateurs ---------------------------------------------------------------------------------


def _count_active_lines(db: Session, condition: ColumnElement[bool], store_id: int | None) -> int:
    stmt = (
        select(func.count())
        .select_from(Stock)
        .join(Stock.product)
        .where(condition, Product.is_active.is_(True))
    )
    if store_id is not None:
        stmt = stmt.where(Stock.store_id == store_id)
    return db.scalar(stmt) or 0


def count_low_stock(db: Session, store_id: int | None) -> int:
    return _count_active_lines(db, Stock.low_stock, store_id)


def count_out_of_stock(db: Session, store_id: int | None) -> int:
    return _count_active_lines(db, Stock.out_of_stock, store_id)


def total_quantity(db: Session, store_id: int | None) -> int:
    stmt = select(func.coalesce(func.sum(Stock.quantity), 0))
    if store_id is not None:
        stmt = stmt.where(Stock.store_id == store_id)
    return db.scalar(stmt) or 0


def count_unavailable_products(db: Session) -> int:
    """Produits actifs dont la quantité est nulle dans TOUS les magasins (réellement indisponibles)."""
    total_by_product = (
        select(func.coalesce(func.sum(Stock.quantity), 0))
        .where(Stock.product_id == Product.id)
        .correlate(Product)
        .scalar_subquery()
    )
    stmt = select(func.count()).select_from(Product).where(Product.is_active.is_(True), total_by_product == 0)
    return db.scalar(stmt) or 0


def stock_value_by_store(
    db: Session, store_id: int | None, product_id: int | None = None
) -> list[sa.Row[Any]]:
    """Quantité, valeur d'achat et valeur de vente du stock, magasin par magasin
    (éventuellement pour un seul produit)."""
    stock_join = Stock.store_id == Store.id
    if product_id is not None:
        stock_join = and_(stock_join, Stock.product_id == product_id)
    stmt = (
        select(
            Store,
            func.coalesce(func.sum(Stock.quantity), 0).label("quantity"),
            func.coalesce(func.sum(Stock.quantity * Product.purchase_price), Decimal("0")).label(
                "purchase_value"
            ),
            func.coalesce(func.sum(Stock.quantity * Product.selling_price), Decimal("0")).label("sale_value"),
        )
        .outerjoin(Stock, stock_join)
        .outerjoin(Product, Product.id == Stock.product_id)
        .group_by(Store.id)
        .order_by(Store.is_central.desc(), Store.name)
    )
    if store_id is not None:
        stmt = stmt.where(Store.id == store_id)
    return list(db.execute(stmt))


# --- Mouvements ----------------------------------------------------------------------------------


def list_movements(db: Session, filters: StockMovementFilters) -> PageResult[StockMovement]:
    stmt = select(StockMovement)
    if filters.product_id is not None:
        stmt = stmt.where(StockMovement.product_id == filters.product_id)
    if filters.store_id is not None:
        stmt = stmt.where(StockMovement.store_id == filters.store_id)
    if filters.user_id is not None:
        stmt = stmt.where(StockMovement.user_id == filters.user_id)
    if filters.type is not None:
        stmt = stmt.where(StockMovement.type == filters.type)
    if filters.reference:
        stmt = stmt.where(StockMovement.reference == filters.reference)
    stmt = stmt.where(*date_range_filter(StockMovement.created_at, filters.date_from, filters.date_to))
    stmt = apply_sort(stmt, filters.sort, MOVEMENT_SORT_FIELDS, "-created_at", StockMovement.id)
    return paginate(db, stmt, filters.page, filters.page_size)
