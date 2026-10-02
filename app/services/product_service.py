from sqlalchemy.orm import Session

from app.core.exceptions import BusinessRuleError, ConflictError, NotFoundError
from app.models import Category, Product, User
from app.repositories import product_repository
from app.repositories.base import PageResult
from app.schemas.product import ProductCreate, ProductFilters, ProductRead, ProductUpdate
from app.services import audit_service
from app.services.category_service import get_category
from app.utils.text import display_text


def list_products(db: Session, filters: ProductFilters) -> PageResult[Product]:
    return product_repository.list_products(db, filters)


def get_product(db: Session, product_id: int) -> Product:
    product = db.get(Product, product_id)
    if product is None:
        raise NotFoundError(f"Produit {product_id} introuvable")
    return product


def _ensure_unique_reference(db: Session, reference: str) -> None:
    if product_repository.get_by_reference(db, reference) is not None:
        raise ConflictError(f"La référence « {display_text(reference)} » est déjà utilisée")


def _get_active_category(db: Session, category_id: int) -> Category:
    category = get_category(db, category_id)
    if not category.is_active:
        raise BusinessRuleError(f"La catégorie « {display_text(category.name)} » est désactivée")
    return category


def create_product(db: Session, actor: User, data: ProductCreate, ip_address: str | None = None) -> Product:
    """Crée un produit au catalogue. Son stock démarre à 0 et s'alimente par une entrée de stock."""
    _ensure_unique_reference(db, data.reference)
    category = _get_active_category(db, data.category_id) if data.category_id is not None else None

    product = Product(**data.model_dump(exclude={"category_id"}), category=category, stock=0)
    db.add(product)
    db.flush()
    audit_service.record(
        db,
        user_id=actor.id,
        action="product.create",
        entity_type="product",
        entity_id=product.id,
        new_data=audit_service.snapshot(ProductRead, product),
        ip_address=ip_address,
    )
    db.commit()
    return product


def update_product(
    db: Session, actor: User, product_id: int, data: ProductUpdate, ip_address: str | None = None
) -> Product:
    product = get_product(db, product_id)
    changes = data.changes()
    if "reference" in changes and changes["reference"] != product.reference:
        _ensure_unique_reference(db, changes["reference"])

    old_data = audit_service.snapshot(ProductRead, product)
    if "category_id" in changes:
        category_id = changes.pop("category_id")
        product.category = _get_active_category(db, category_id) if category_id is not None else None
    for field, value in changes.items():
        setattr(product, field, value)
    db.flush()
    audit_service.record(
        db,
        user_id=actor.id,
        action="product.update",
        entity_type="product",
        entity_id=product.id,
        old_data=old_data,
        new_data=audit_service.snapshot(ProductRead, product),
        ip_address=ip_address,
    )
    db.commit()
    return product


def delete_product(db: Session, actor: User, product_id: int, ip_address: str | None = None) -> None:
    """Suppression logique : le produit est désactivé (donc non vendable), l'historique est conservé."""
    product = get_product(db, product_id)
    old_data = audit_service.snapshot(ProductRead, product)
    product.is_active = False
    audit_service.record(
        db,
        user_id=actor.id,
        action="product.delete",
        entity_type="product",
        entity_id=product.id,
        old_data=old_data,
        ip_address=ip_address,
    )
    db.commit()
