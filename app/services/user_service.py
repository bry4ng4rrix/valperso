from sqlalchemy.orm import Session

from app.core.exceptions import BusinessRuleError, ConflictError, NotFoundError, PermissionDeniedError
from app.core.permissions import RoleName, is_admin
from app.core.security import hash_password
from app.models import Role, User
from app.repositories import user_repository
from app.repositories.base import PageResult
from app.schemas.user import UserCreate, UserFilters, UserRead, UserUpdate
from app.services import audit_service, store_access
from app.utils.text import display_text


def list_users(db: Session, filters: UserFilters) -> PageResult[User]:
    return user_repository.list_users(db, filters)


def get_user(db: Session, user_id: int) -> User:
    user = db.get(User, user_id)
    if user is None:
        raise NotFoundError("Utilisateur introuvable")
    return user


def _get_role(db: Session, role_id: int) -> Role:
    role = db.get(Role, role_id)
    if role is None:
        raise NotFoundError(f"Rôle {role_id} introuvable")
    return role


def _ensure_can_grant_role(actor: User, role: Role) -> None:
    # Sans cette règle, un MANAGER ayant user.create pourrait se créer un compte ADMIN.
    if role.name == RoleName.ADMIN and not is_admin(actor):
        raise PermissionDeniedError("Seul un administrateur peut attribuer le rôle ADMIN")


def _ensure_can_manage(actor: User, target: User) -> None:
    if is_admin(target) and not is_admin(actor):
        raise PermissionDeniedError("Seul un administrateur peut modifier un compte administrateur")


def _ensure_unique_username(db: Session, username: str) -> None:
    if user_repository.get_by_username(db, username) is not None:
        raise ConflictError(f"Le nom d'utilisateur « {display_text(username)} » est déjà utilisé")


def _ensure_unique_email(db: Session, email: str) -> None:
    if user_repository.get_by_email(db, email) is not None:
        raise ConflictError(f"L'email « {email} » est déjà utilisé")


def create_user(db: Session, actor: User, data: UserCreate, ip_address: str | None = None) -> User:
    _ensure_unique_username(db, data.username)
    if data.email:
        _ensure_unique_email(db, data.email)
    role = _get_role(db, data.role_id)
    _ensure_can_grant_role(actor, role)
    if data.store_id is not None:
        store_access.get_active_store(db, data.store_id)

    user = User(
        **data.model_dump(exclude={"password", "role_id"}),
        role=role,
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


def update_user(
    db: Session, actor: User, user_id: int, data: UserUpdate, ip_address: str | None = None
) -> User:
    user = get_user(db, user_id)
    _ensure_can_manage(actor, user)
    changes = data.changes()

    if "username" in changes and changes["username"] != user.username:
        _ensure_unique_username(db, changes["username"])
    if changes.get("email") and changes["email"] != user.email:
        _ensure_unique_email(db, changes["email"])
    if changes.get("store_id") is not None:
        store_access.get_active_store(db, changes["store_id"])
    if user.id == actor.id and changes.get("is_active") is False:
        raise BusinessRuleError("Vous ne pouvez pas désactiver votre propre compte")

    old_data = audit_service.snapshot(UserRead, user)
    if "role_id" in changes:
        role = _get_role(db, changes.pop("role_id"))
        _ensure_can_grant_role(actor, role)
        user.role = role
    password = changes.pop("password", None)
    if password is not None:
        user.password_hash = hash_password(password)
    for field, value in changes.items():
        setattr(user, field, value)
    db.flush()

    new_data = audit_service.snapshot(UserRead, user) | {"password_changed": password is not None}
    audit_service.record(
        db,
        user_id=actor.id,
        action="user.update",
        entity_type="user",
        entity_id=user.id,
        old_data=old_data,
        new_data=new_data,
        ip_address=ip_address,
    )
    db.commit()
    return user


def delete_user(db: Session, actor: User, user_id: int, ip_address: str | None = None) -> None:
    """Suppression logique : le compte est désactivé, son historique (ventes, mouvements) est conservé."""
    user = get_user(db, user_id)
    if user.id == actor.id:
        raise BusinessRuleError("Vous ne pouvez pas supprimer votre propre compte")
    _ensure_can_manage(actor, user)

    old_data = audit_service.snapshot(UserRead, user)
    user.is_active = False
    audit_service.record(
        db,
        user_id=actor.id,
        action="user.delete",
        entity_type="user",
        entity_id=user.id,
        old_data=old_data,
        ip_address=ip_address,
    )
    db.commit()
