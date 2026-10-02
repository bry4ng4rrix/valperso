from sqlalchemy.orm import Session

from app.core.exceptions import BusinessRuleError, ConflictError
from app.models import Store, User
from app.repositories import store_repository
from app.repositories.base import PageResult
from app.schemas.store import StoreCreate, StoreFilters, StoreRead, StoreUpdate
from app.services import audit_service
from app.services.store_access import get_store_or_404
from app.utils.text import display_text

DEFAULT_STORE_NAME = "STOCK LOCAL"


def list_stores(db: Session, filters: StoreFilters) -> PageResult[Store]:
    return store_repository.list_stores(db, filters)


def get_store(db: Session, store_id: int) -> Store:
    return get_store_or_404(db, store_id)


def _ensure_unique_name(db: Session, name: str) -> None:
    if store_repository.get_by_name(db, name) is not None:
        raise ConflictError(f"Un magasin nommé « {display_text(name)} » existe déjà")


def create_store(db: Session, actor: User, data: StoreCreate, ip_address: str | None = None) -> Store:
    _ensure_unique_name(db, data.name)
    store = Store(**data.model_dump())
    db.add(store)
    db.flush()
    audit_service.record(
        db,
        user_id=actor.id,
        action="store.create",
        entity_type="store",
        entity_id=store.id,
        new_data=audit_service.snapshot(StoreRead, store),
        ip_address=ip_address,
    )
    db.commit()
    return store


def update_store(
    db: Session, actor: User, store_id: int, data: StoreUpdate, ip_address: str | None = None
) -> Store:
    store = get_store_or_404(db, store_id)
    changes = data.changes()
    if "name" in changes and changes["name"] != store.name:
        _ensure_unique_name(db, changes["name"])
    if store.is_default and changes.get("is_active") is False:
        raise BusinessRuleError("Le STOCK LOCAL (magasin par défaut) ne peut pas être désactivé")

    old_data = audit_service.snapshot(StoreRead, store)
    for field, value in changes.items():
        setattr(store, field, value)
    db.flush()
    audit_service.record(
        db,
        user_id=actor.id,
        action="store.update",
        entity_type="store",
        entity_id=store.id,
        old_data=old_data,
        new_data=audit_service.snapshot(StoreRead, store),
        ip_address=ip_address,
    )
    db.commit()
    return store


def delete_store(db: Session, actor: User, store_id: int, ip_address: str | None = None) -> None:
    """Suppression logique : le magasin est désactivé, son historique est conservé."""
    store = get_store_or_404(db, store_id)
    if store.is_default:
        raise BusinessRuleError("Le STOCK LOCAL (magasin par défaut) ne peut pas être supprimé")

    old_data = audit_service.snapshot(StoreRead, store)
    store.is_active = False
    audit_service.record(
        db,
        user_id=actor.id,
        action="store.delete",
        entity_type="store",
        entity_id=store.id,
        old_data=old_data,
        ip_address=ip_address,
    )
    db.commit()
