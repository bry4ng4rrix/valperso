"""Isolation des magasins : règle de sécurité appliquée par tous les modules.

- Un ADMIN peut gérer tous les magasins. S'il ne précise pas de magasin, ses opérations
  s'appliquent au Stock Local (stock central).
- Un VENDEUR travaille uniquement dans son magasin (`current_user.store_id`). Un `store_id`
  différent envoyé par le frontend est refusé (InvalidStoreAccess) : il n'est jamais cru.
"""

from sqlalchemy.orm import Session

from app.core.exceptions import BusinessRuleError, InactiveStore, InvalidStoreAccess, StoreNotFound
from app.core.permissions import is_admin
from app.models import Store, User
from app.repositories import store_repository
from app.utils.text import display_text


def own_store_id(user: User) -> int:
    """Magasin d'un vendeur. Un vendeur sans magasin ne peut réaliser aucune opération de magasin."""
    if user.store_id is None:
        raise InvalidStoreAccess("Vous n'êtes affecté à aucun magasin : contactez un administrateur")
    return user.store_id


def ensure_store_access(user: User, store_id: int) -> None:
    if not is_admin(user) and own_store_id(user) != store_id:
        raise InvalidStoreAccess()


def visible_store_id(user: User, requested_store_id: int | None) -> int | None:
    """Magasin utilisé pour filtrer une liste ou une statistique (None = tous les magasins)."""
    if is_admin(user):
        return requested_store_id
    store_id = own_store_id(user)
    if requested_store_id is not None and requested_store_id != store_id:
        raise InvalidStoreAccess()
    return store_id


def get_store(db: Session, store_id: int) -> Store:
    store = db.get(Store, store_id)
    if store is None:
        raise StoreNotFound(f"Magasin {store_id} introuvable")
    return store


def get_active_store(db: Session, store_id: int) -> Store:
    store = get_store(db, store_id)
    if not store.is_active:
        raise InactiveStore(f"Le magasin « {display_text(store.name)} » est désactivé")
    return store


def get_central_store(db: Session) -> Store:
    store = store_repository.get_central(db)
    if store is None:
        raise BusinessRuleError("Le Stock Local n'existe pas : lancez le script de seed (python -m app.seed)")
    return store


def resolve_operation_store(db: Session, user: User, requested_store_id: int | None) -> Store:
    """Magasin dans lequel s'effectue une opération (vente, mouvement de stock, transfert, caisse)."""
    if not is_admin(user):
        return get_active_store(db, visible_store_id(user, requested_store_id))
    if requested_store_id is not None:
        return get_active_store(db, requested_store_id)
    return get_active_store(db, get_central_store(db).id)
