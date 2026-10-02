"""Gestion des utilisateurs par l'ADMIN : comptes, rôle, affectation au magasin, statut.

Un co-administrateur est simplement un utilisateur dont le rôle est ADMIN.
"""

from sqlalchemy.orm import Session

from app.core.exceptions import BusinessRuleError, ConflictError, PermissionDenied, UserNotFound
from app.core.permissions import RoleName, is_admin
from app.core.security import hash_password
from app.models import Role, Store, User
from app.repositories import role_repository, user_repository
from app.repositories.base import PageResult
from app.schemas.common import Pagination
from app.schemas.user import (
    UserCreate,
    UserFilters,
    UserRead,
    UserRoleUpdate,
    UserStatusUpdate,
    UserStoreUpdate,
    UserUpdate,
)
from app.services import audit_service, store_access
from app.utils.text import display_text

# --- Consultation --------------------------------------------------------------------------------


def list_users(db: Session, filters: UserFilters) -> PageResult[User]:
    return user_repository.list_users(db, filters)


def get_user(db: Session, user_id: int) -> User:
    user = db.get(User, user_id)
    if user is None:
        raise UserNotFound()
    return user


def list_store_employees(db: Session, store_id: int, pagination: Pagination) -> PageResult[User]:
    store_access.get_store(db, store_id)
    return user_repository.list_store_employees(db, store_id, pagination)


# --- Règles communes -----------------------------------------------------------------------------


def _get_role(db: Session, role_name: RoleName) -> Role:
    role = role_repository.get_by_name(db, role_name)
    if role is None:
        raise BusinessRuleError(f"Le rôle {role_name} n'existe pas : lancez le script de seed")
    return role


def _ensure_can_grant_role(actor: User, role: Role) -> None:
    # Sans cette règle, un utilisateur ayant reçu user.create pourrait se créer un compte ADMIN.
    if role.name == RoleName.ADMIN and not is_admin(actor):
        raise PermissionDenied("Seul un ADMIN peut attribuer le rôle ADMIN")


def _ensure_can_manage(actor: User, target: User) -> None:
    if is_admin(target) and not is_admin(actor):
        raise PermissionDenied("Seul un ADMIN peut modifier un compte ADMIN")


def _ensure_not_last_admin(db: Session, target: User) -> None:
    if is_admin(target) and target.is_active and user_repository.count_active_admins(db) <= 1:
        raise BusinessRuleError("Opération impossible : c'est le dernier ADMIN actif")


def _ensure_unique_username(db: Session, username: str) -> None:
    if user_repository.get_by_username(db, username) is not None:
        raise ConflictError(f"Le nom d'utilisateur « {display_text(username)} » est déjà utilisé")


def _ensure_unique_email(db: Session, email: str) -> None:
    if user_repository.get_by_email(db, email) is not None:
        raise ConflictError(f"L'email « {email} » est déjà utilisé")


def _get_assignable_store(db: Session, store_id: int | None) -> Store | None:
    return store_access.get_active_store(db, store_id) if store_id is not None else None


def _save_change(
    db: Session, actor: User, user: User, action: str, old_data: dict, ip_address: str | None, **extra
) -> User:
    db.flush()
    audit_service.record(
        db,
        user_id=actor.id,
        action=action,
        entity_type="user",
        entity_id=user.id,
        old_data=old_data,
        new_data=audit_service.snapshot(UserRead, user) | extra,
        ip_address=ip_address,
    )
    db.commit()
    return user


# --- Création et modification --------------------------------------------------------------------


def create_user(db: Session, actor: User, data: UserCreate, ip_address: str | None = None) -> User:
    """Crée un VENDEUR ou un ADMIN (un ADMIN peut créer d'autres ADMIN)."""
    _ensure_unique_username(db, data.username)
    if data.email:
        _ensure_unique_email(db, data.email)
    role = _get_role(db, data.role)
    _ensure_can_grant_role(actor, role)

    user = User(
        **data.model_dump(exclude={"password", "role", "store_id"}),
        role=role,
        store=_get_assignable_store(db, data.store_id),
        password_hash=hash_password(data.password),
    )
    db.add(user)
    db.flush()
    audit_service.record(
        db,
        user_id=actor.id,
        action="user.create",
        entity_type="user",
        entity_id=user.id,
        new_data=audit_service.snapshot(UserRead, user),
        ip_address=ip_address,
    )
    db.commit()
    return user


def update_user(db: Session, actor: User, user_id: int, data: UserUpdate, ip_address: str | None = None) -> User:
    user = get_user(db, user_id)
    _ensure_can_manage(actor, user)
    if data.username != user.username:
        _ensure_unique_username(db, data.username)
    if data.email and data.email != user.email:
        _ensure_unique_email(db, data.email)

    old_data = audit_service.snapshot(UserRead, user)
    for field, value in data.model_dump(exclude={"password"}).items():
        setattr(user, field, value)
    if data.password is not None:
        user.password_hash = hash_password(data.password)
    return _save_change(
        db, actor, user, "user.update", old_data, ip_address, password_changed=data.password is not None
    )


def change_role(
    db: Session, actor: User, user_id: int, data: UserRoleUpdate, ip_address: str | None = None
) -> User:
    user = get_user(db, user_id)
    _ensure_can_manage(actor, user)
    role = _get_role(db, data.role)
    _ensure_can_grant_role(actor, role)
    if role.id == user.role_id:
        return user
    _ensure_not_last_admin(db, user)

    old_data = audit_service.snapshot(UserRead, user)
    user.role = role
    return _save_change(db, actor, user, "user.role_change", old_data, ip_address)


def change_store(
    db: Session, actor: User, user_id: int, data: UserStoreUpdate, ip_address: str | None = None
) -> User:
    """Affecte l'utilisateur à un magasin, le change de magasin ou retire l'affectation (null)."""
    user = get_user(db, user_id)
    _ensure_can_manage(actor, user)
    store = _get_assignable_store(db, data.store_id)

    old_data = audit_service.snapshot(UserRead, user)
    user.store = store
    return _save_change(db, actor, user, "user.store_change", old_data, ip_address)


def change_status(
    db: Session, actor: User, user_id: int, data: UserStatusUpdate, ip_address: str | None = None
) -> User:
    user = get_user(db, user_id)
    _ensure_can_manage(actor, user)
    if not data.is_active:
        if user.id == actor.id:
            raise BusinessRuleError("Vous ne pouvez pas désactiver votre propre compte")
        _ensure_not_last_admin(db, user)

    old_data = audit_service.snapshot(UserRead, user)
    user.is_active = data.is_active
    return _save_change(db, actor, user, "user.status_change", old_data, ip_address)


def delete_user(db: Session, actor: User, user_id: int, ip_address: str | None = None) -> None:
    """Suppression logique : le compte est désactivé, son historique (ventes, paiements) est conservé."""
    change_status(db, actor, user_id, UserStatusUpdate(is_active=False), ip_address)
