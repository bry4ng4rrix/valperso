from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import Product
from app.repositories.base import PageResult, apply_sort, paginate, search_filter
from app.schemas.product import ProductFilters

SORT_FIELDS = {
    "name": Product.name,
    "reference": Product.reference,
    "selling_price": Product.selling_price,
    "created_at": Product.created_at,
}


def list_products(db: Session, filters: ProductFilters) -> PageResult[Product]:
    stmt = select(Product)
    if filters.search:
        stmt = stmt.where(search_filter(filters.search, Product.reference, Product.name))
    if filters.category_id is not None:
        stmt = stmt.where(Product.category_id == filters.category_id)
    if filters.is_active is not None:
        stmt = stmt.where(Product.is_active == filters.is_active)
    stmt = apply_sort(stmt, filters.sort, SORT_FIELDS, "name", Product.id)
    return paginate(db, stmt, filters.page, filters.page_size)


def count_active(db: Session) -> int:
    return db.scalar(select(func.count()).select_from(Product).where(Product.is_active.is_(True))) or 0
