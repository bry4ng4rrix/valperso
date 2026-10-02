"""Catalogue des produits. Ni la référence ni le nom ne sont uniques : seul l'id identifie un produit."""

from decimal import Decimal

from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.exceptions import InactiveProduct, InvalidSellingPrice, ProductNotFound
from app.models import Category, Product, Stock, User
from app.repositories import product_repository
from app.repositories.base import PageResult
from app.schemas.product import ProductCreate, ProductFilters, ProductRead, ProductUpdate
from app.services import audit_service, store_access
from app.services.category_service import get_active_category
from app.utils.text import display_text


def list_products(db: Session, filters: ProductFilters) -> PageResult[Product]:
    return product_repository.list_products(db, filters)


def get_product(db: Session, product_id: int) -> Product:
    product = db.get(Product, product_id)
    if product is None:
        raise ProductNotFound(f"Produit {product_id} introuvable")
    return product


def get_active_product(db: Session, product_id: int) -> Product:
    product = get_product(db, product_id)
    if not product.is_active:
        raise InactiveProduct(f"Le produit « {display_text(product.reference)} » est désactivé")
    return product


def ensure_valid_prices(purchase_price: Decimal, selling_price: Decimal) -> None:
    """Règle métier : prix de vente >= prix de stock. Vérifiée ici même si le schéma l'a déjà
    contrôlée, pour que la règle tienne quel que soit l'appelant du service."""
    if selling_price < purchase_price:
        raise InvalidSellingPrice()


def _audit(
    db: Session,
    actor: User,
    product: Product,
    action: str,
    ip_address: str | None,
    old_data: dict | None = None,
) -> None:
    db.flush()
    audit_service.record(
        db,
        user_id=actor.id,
        action=action,
        entity_type="product",
        entity_id=product.id,
        old_data=old_data,
        new_data=audit_service.snapshot(ProductRead, product),
        ip_address=ip_address,
    )


def create_product(db: Session, actor: User, data: ProductCreate, ip_address: str | None = None) -> Product:
    """Crée le produit et sa ligne de stock à 0 dans le Stock Local."""
    ensure_valid_prices(data.purchase_price, data.selling_price)
    category = get_active_category(db, data.category_id) if data.category_id is not None else None
    central = store_access.get_central_store(db)

    product = Product(**data.model_dump(exclude={"category_id"}), category=category)
    product.stocks.append(
        Stock(store_id=central.id, quantity=0, alert_threshold=settings.DEFAULT_ALERT_THRESHOLD)
    )
    db.add(product)
    _audit(db, actor, product, "product.create", ip_address)
    db.commit()
    return product


def update_product(
    db: Session, actor: User, product_id: int, data: ProductUpdate, ip_address: str | None = None
) -> Product:
    product = get_product(db, product_id)
    changes = data.changes()
    # Un seul prix peut être envoyé : on compare avec l'autre prix déjà enregistré.
    ensure_valid_prices(
        changes.get("purchase_price", product.purchase_price),
        changes.get("selling_price", product.selling_price),
    )
    category: Category | None = product.category
    if "category_id" in changes:
        category_id = changes.pop("category_id")
        category = get_active_category(db, category_id) if category_id is not None else None

    old_data = audit_service.snapshot(ProductRead, product)
    product.category = category
    for field, value in changes.items():
        setattr(product, field, value)
    _audit(db, actor, product, "product.update", ip_address, old_data)
    db.commit()
    return product


def delete_product(db: Session, actor: User, product_id: int, ip_address: str | None = None) -> None:
    """Suppression logique : le produit devient non vendable, son historique et son stock sont conservés."""
    product = get_product(db, product_id)
    old_data = audit_service.snapshot(ProductRead, product)
    product.is_active = False
    _audit(db, actor, product, "product.delete", ip_address, old_data)
    db.commit()
