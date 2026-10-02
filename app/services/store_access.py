"""Règles d'accès aux magasins, communes à tous les modules.

- Un utilisateur rattaché à un magasin (`store_id` renseigné) n'opère et ne consulte que ce magasin.
- Un utilisateur non rattaché (`store_id` NULL, ex. l'administrateur) accède à tous les magasins.
  S'il ne précise pas de magasin, ses opérations s'appliquent au STOCK LOCAL (magasin par défaut).
"""

from sqlalchemy.orm import Session

from app.core.exceptions import BusinessRuleError, NotFoundError, PermissionDeniedError
from app.models import Store, User
from app.repositories import store_repository
from app.utils.text import display_text


def ensure_store_access(user: User, store_id: int) -> None:
    if user.store_id is not None and user.store_id != store_id:
        raise PermissionDeniedError("Vous n'avez pas accès à ce magasin", code="STORE_ACCESS_DENIED")


def visible_store_id(user: User, requested_store_id: int | None) -> int | None:
    """Magasin à utiliser pour filtrer une liste (None = tous les magasins)."""
    if user.store_id is None:
        return requested_store_id
    if requested_store_id is not None:
        ensure_store_access(user, requested_store_id)
    return user.store_id


def get_store_or_404(db: Session, store_id: int) -> Store:
    store = db.get(Store, store_id)
    if store is None:
        raise NotFoundError(f"Magasin {store_id} introuvable")
    return store


def get_active_store(db: Session, store_id: int) -> Store:
    store = get_store_or_404(db, store_id)
    if not store.is_active:
        raise BusinessRuleError(
            f"Le magasin « {display_text(store.name)} » est désactivé", code="STORE_INACTIVE"
        )
    return store


def get_default_store(db: Session) -> Store:
    store = store_repository.get_default(db)
    if store is None:
        raise BusinessRuleError(
            "Aucun magasin par défaut (STOCK LOCAL). Lancez le script de seed : python -m app.seed",
            code="NO_DEFAULT_STORE",
        )
    return store


def resolve_operation_store(db: Session, user: User, requested_store_id: int | None) -> Store:
    """Magasin dans lequel s'effectue une opération (vente, mouvement de stock, caisse...)."""
    if requested_store_id is not None:
        ensure_store_access(user, requested_store_id)
        return get_active_store(db, requested_store_id)
    if user.store_id is not None:
        return get_active_store(db, user.store_id)
    return get_active_store(db, get_default_store(db).id)
