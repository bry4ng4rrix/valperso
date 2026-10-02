from sqlalchemy.orm import Session

from app.core.exceptions import BusinessRuleError, ConflictError, NotFoundError
from app.models import Category, User
from app.repositories import category_repository
from app.repositories.base import PageResult
from app.schemas.category import CategoryCreate, CategoryFilters, CategoryRead, CategoryUpdate
from app.services import audit_service
from app.utils.text import display_text


def list_categories(db: Session, filters: CategoryFilters) -> PageResult[Category]:
    return category_repository.list_categories(db, filters)


def get_category(db: Session, category_id: int) -> Category:
    category = db.get(Category, category_id)
    if category is None:
        raise NotFoundError(f"Catégorie {category_id} introuvable")
    return category


def get_active_category(db: Session, category_id: int) -> Category:
    category = get_category(db, category_id)
    if not category.is_active:
        raise BusinessRuleError(f"La catégorie « {display_text(category.name)} » est désactivée")
    return category


def _ensure_unique_name(db: Session, name: str) -> None:
    if category_repository.get_by_name(db, name) is not None:
        raise ConflictError(f"La catégorie « {display_text(name)} » existe déjà")


def create_category(
    db: Session, actor: User, data: CategoryCreate, ip_address: str | None = None
) -> Category:
    _ensure_unique_name(db, data.name)
    category = Category(**data.model_dump())
    db.add(category)
    db.flush()
    audit_service.record(
        db,
        user_id=actor.id,
        action="category.create",
        entity_type="category",
        entity_id=category.id,
        new_data=audit_service.snapshot(CategoryRead, category),
        ip_address=ip_address,
    )
    db.commit()
    return category


def update_category(
    db: Session, actor: User, category_id: int, data: CategoryUpdate, ip_address: str | None = None
) -> Category:
    category = get_category(db, category_id)
    changes = data.changes()
    if "name" in changes and changes["name"] != category.name:
        _ensure_unique_name(db, changes["name"])

    old_data = audit_service.snapshot(CategoryRead, category)
    for field, value in changes.items():
        setattr(category, field, value)
    db.flush()
    audit_service.record(
        db,
        user_id=actor.id,
        action="category.update",
        entity_type="category",
        entity_id=category.id,
        old_data=old_data,
        new_data=audit_service.snapshot(CategoryRead, category),
        ip_address=ip_address,
    )
    db.commit()
    return category


def delete_category(db: Session, actor: User, category_id: int, ip_address: str | None = None) -> None:
    """Suppression logique : la catégorie est désactivée, ses produits restent intacts."""
    category = get_category(db, category_id)
    old_data = audit_service.snapshot(CategoryRead, category)
    category.is_active = False
    audit_service.record(
        db,
        user_id=actor.id,
        action="category.delete",
        entity_type="category",
        entity_id=category.id,
        old_data=old_data,
        ip_address=ip_address,
    )
    db.commit()
