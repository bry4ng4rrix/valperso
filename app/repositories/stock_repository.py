from collections.abc import Iterable

from sqlalchemy import ColumnElement, func, or_, select
from sqlalchemy.orm import Session

from app.models import Product, StockMovement, StockTransfer, StoreStock
from app.models.enums import StockStatus
from app.repositories.base import PageResult, apply_sort, date_range_filter, paginate, search_filter
from app.schemas.stock import StockMovementFilters, StockTransferFilters, StoreStockFilters

STORE_STOCK_SORT_FIELDS = {
    "name": Product.name,
    "reference": Product.reference,
    "quantity": StoreStock.quantity,
    "updated_at": StoreStock.updated_at,
}
MOVEMENT_SORT_FIELDS = {"created_at": StockMovement.created_at, "quantity": StockMovement.quantity}
TRANSFER_SORT_FIELDS = {"created_at": StockTransfer.created_at, "quantity": StockTransfer.quantity}


# --- Articles par magasin ------------------------------------------------------------------------


def get_line(db: Session, store_id: int, product_id: int) -> StoreStock | None:
    return db.scalar(
        select(StoreStock).where(StoreStock.store_id == store_id, StoreStock.product_id == product_id)
    )


def lock_lines(db: Session, store_id: int, product_ids: Iterable[int]) -> dict[int, StoreStock]:
    """Lignes de stock d'un magasin, verrouillées jusqu'au COMMIT (clé : product_id)."""
    stmt = (
        select(StoreStock)
        .where(StoreStock.store_id == store_id, StoreStock.product_id.in_(sorted(set(product_ids))))
        .order_by(StoreStock.product_id)
        .with_for_update(of=StoreStock)
    )
    return {line.product_id: line for line in db.scalars(stmt)}


def _status_condition(status: StockStatus, threshold: int) -> ColumnElement[bool]:
    if status == StockStatus.OUT_OF_STOCK:
        return StoreStock.quantity <= 0
    if status == StockStatus.LOW_STOCK:
        return (StoreStock.quantity > 0) & (StoreStock.quantity <= threshold)
    return StoreStock.quantity > threshold


def list_store_stock(
    db: Session, store_id: int, filters: StoreStockFilters, low_stock_threshold: int
) -> PageResult[StoreStock]:
    stmt = select(StoreStock).join(StoreStock.product).where(StoreStock.store_id == store_id)
    if filters.search:
        stmt = stmt.where(search_filter(filters.search, Product.reference, Product.name))
    if filters.category_id is not None:
        stmt = stmt.where(Product.category_id == filters.category_id)
    if filters.status is not None:
        stmt = stmt.where(_status_condition(filters.status, low_stock_threshold))
    stmt = apply_sort(stmt, filters.sort, STORE_STOCK_SORT_FIELDS, "name", StoreStock.id)
    return paginate(db, stmt, filters.page, filters.size)


def _low_stock_query(store_id: int | None, threshold: int):
    stmt = (
        select(StoreStock)
        .join(StoreStock.product)
        .where(Product.is_active.is_(True), StoreStock.quantity <= threshold)
    )
    if store_id is not None:
        stmt = stmt.where(StoreStock.store_id == store_id)
    return stmt


def list_low_stock(
    db: Session, store_id: int | None, threshold: int, page: int, size: int
) -> PageResult[StoreStock]:
    stmt = _low_stock_query(store_id, threshold).order_by(StoreStock.quantity, Product.name, StoreStock.id)
    return paginate(db, stmt, page, size)


def count_low_stock(db: Session, store_id: int | None, threshold: int) -> int:
    stmt = _low_stock_query(store_id, threshold)
    return db.scalar(select(func.count()).select_from(stmt.subquery())) or 0


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
    return paginate(db, stmt, filters.page, filters.size)


# --- Transferts ----------------------------------------------------------------------------------


def list_transfers(db: Session, filters: StockTransferFilters) -> PageResult[StockTransfer]:
    stmt = select(StockTransfer)
    if filters.product_id is not None:
        stmt = stmt.where(StockTransfer.product_id == filters.product_id)
    if filters.store_id is not None:
        stmt = stmt.where(
            or_(
                StockTransfer.source_store_id == filters.store_id,
                StockTransfer.destination_store_id == filters.store_id,
            )
        )
    if filters.source_store_id is not None:
        stmt = stmt.where(StockTransfer.source_store_id == filters.source_store_id)
    if filters.destination_store_id is not None:
        stmt = stmt.where(StockTransfer.destination_store_id == filters.destination_store_id)
    stmt = stmt.where(*date_range_filter(StockTransfer.created_at, filters.date_from, filters.date_to))
    stmt = apply_sort(stmt, filters.sort, TRANSFER_SORT_FIELDS, "-created_at", StockTransfer.id)
    return paginate(db, stmt, filters.page, filters.size)
