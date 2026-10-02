import re
from decimal import Decimal, InvalidOperation

from sqlalchemy import ColumnElement, func, or_, select
from sqlalchemy.orm import Session

from app.models import Category, Product
from app.repositories.base import PageResult, apply_sort, paginate, search_filter
from app.schemas.product import ProductFilters

SORT_FIELDS = {
    "name": Product.name,
    "reference": Product.reference,
    "selling_price": Product.selling_price,
    "created_at": Product.created_at,
}


def parse_price(term: str) -> Decimal | None:
    """Montant saisi dans la recherche : « 200000 », « 200 000 », « 200 000 Ar », « 1500,50 »."""
    cleaned = re.sub(r"\s+|ar$", "", term.strip().lower()).replace(",", ".")
    if not re.fullmatch(r"\d+(\.\d{1,2})?", cleaned):
        return None
    try:
        return Decimal(cleaned)
    except InvalidOperation:
        return None


def search_condition(term: str) -> ColumnElement[bool]:
    """Recherche d'un produit : nom, référence ou catégorie contenant le texte, ou prix (de vente
    ou d'achat) égal au montant saisi."""
    conditions = [
        search_filter(term, Product.reference, Product.name),
        Product.category.has(search_filter(term, Category.name)),
    ]
    price = parse_price(term)
    if price is not None:
        conditions += [Product.selling_price == price, Product.purchase_price == price]
    return or_(*conditions)


def list_products(db: Session, filters: ProductFilters) -> PageResult[Product]:
    stmt = select(Product)
    if filters.search:
        stmt = stmt.where(search_condition(filters.search))
    if filters.category_id is not None:
        stmt = stmt.where(Product.category_id == filters.category_id)
    if filters.is_active is not None:
        stmt = stmt.where(Product.is_active == filters.is_active)
    stmt = apply_sort(stmt, filters.sort, SORT_FIELDS, "name", Product.id)
    return paginate(db, stmt, filters.page, filters.page_size)


def count_active(db: Session) -> int:
    return db.scalar(select(func.count()).select_from(Product).where(Product.is_active.is_(True))) or 0
