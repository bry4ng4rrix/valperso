from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Category
from app.repositories.base import PageResult, apply_sort, paginate, search_filter
from app.schemas.category import CategoryFilters

SORT_FIELDS = {"name": Category.name, "created_at": Category.created_at}


def get_by_name(db: Session, name: str) -> Category | None:
    return db.scalar(select(Category).where(Category.name == name))


def list_categories(db: Session, filters: CategoryFilters) -> PageResult[Category]:
    stmt = select(Category)
    if filters.search:
        stmt = stmt.where(search_filter(filters.search, Category.name, Category.description))
    if filters.is_active is not None:
        stmt = stmt.where(Category.is_active == filters.is_active)
    stmt = apply_sort(stmt, filters.sort, SORT_FIELDS, "name", Category.id)
    return paginate(db, stmt, filters.page, filters.page_size)
