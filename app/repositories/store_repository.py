from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import Store
from app.repositories.base import PageResult, apply_sort, paginate, search_filter
from app.schemas.store import StoreFilters

SORT_FIELDS = {"name": Store.name, "created_at": Store.created_at}


def get_by_name(db: Session, name: str) -> Store | None:
    return db.scalar(select(Store).where(Store.name == name))


def get_central(db: Session) -> Store | None:
    """Le Stock Local : stock central créé par le seed."""
    return db.scalar(select(Store).where(Store.is_central.is_(True)))


def list_stores(db: Session, filters: StoreFilters) -> PageResult[Store]:
    stmt = select(Store)
    if filters.search:
        stmt = stmt.where(search_filter(filters.search, Store.name, Store.address))
    if filters.is_active is not None:
        stmt = stmt.where(Store.is_active == filters.is_active)
    # Le Stock Local apparaît toujours en premier.
    stmt = stmt.order_by(Store.is_central.desc())
    stmt = apply_sort(stmt, filters.sort, SORT_FIELDS, "name", Store.id)
    return paginate(db, stmt, filters.page, filters.page_size)


def count_active(db: Session) -> int:
    return db.scalar(select(func.count()).select_from(Store).where(Store.is_active.is_(True))) or 0
