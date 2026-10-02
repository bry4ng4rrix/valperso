"""Magasins. Un magasin se crée sans vendeur ; les vendeurs y sont affectés depuis la gestion des
utilisateurs (PUT /users/{id}/store)."""

from sqlalchemy.orm import Session

from app.core.exceptions import BusinessRuleError, ConflictError
from app.models import Store, User
from app.repositories import store_repository
from app.repositories.base import PageResult
from app.schemas.store import StoreCreate, StoreFilters, StoreRead, StoreUpdate
from app.services import audit_service
from app.services.store_access import get_store
from app.utils.text import display_text

CENTRAL_STORE_NAME = "STOCK LOCAL"


def list_stores(db: Session, filters: StoreFilters) -> PageResult[Store]:
    return store_repository.list_stores(db, filters)


def _ensure_unique_name(db: Session, name: str) -> None:
    if store_repository.get_by_name(db, name) is not None:
        raise ConflictError(f"Un magasin nommé « {display_text(name)} » existe déjà")


def _audit(
    db: Session, actor: User, store: Store, action: str, ip_address: str | None, old_data: dict | None = None
) -> None:
    db.flush()
    audit_service.record(
        db,
        user_id=actor.id,
        action=action,
        entity_type="store",
        entity_id=store.id,
        old_data=old_data,
        new_data=audit_service.snapshot(StoreRead, store),
        ip_address=ip_address,
    )


def create_store(db: Session, actor: User, data: StoreCreate, ip_address: str | None = None) -> Store:
    _ensure_unique_name(db, data.name)
    store = Store(**data.model_dump())
    db.add(store)
    _audit(db, actor, store, "store.create", ip_address)
    db.commit()
    return store


def update_store(
    db: Session, actor: User, store_id: int, data: StoreUpdate, ip_address: str | None = None
) -> Store:
    store = get_store(db, store_id)
    changes = data.changes()
    if "name" in changes and changes["name"] != store.name:
        _ensure_unique_name(db, changes["name"])
    if store.is_central and changes.get("is_active") is False:
        raise BusinessRuleError("Le Stock Local (stock central) ne peut pas être désactivé")

    old_data = audit_service.snapshot(StoreRead, store)
    for field, value in changes.items():
        setattr(store, field, value)
    _audit(db, actor, store, "store.update", ip_address, old_data)
    db.commit()
    return store


def delete_store(db: Session, actor: User, store_id: int, ip_address: str | None = None) -> None:
    """Suppression logique : le magasin est désactivé, son historique et son stock sont conservés."""
    store = get_store(db, store_id)
    if store.is_central:
        raise BusinessRuleError("Le Stock Local (stock central) ne peut pas être supprimé")

    old_data = audit_service.snapshot(StoreRead, store)
    store.is_active = False
    _audit(db, actor, store, "store.delete", ip_address, old_data)
    db.commit()
