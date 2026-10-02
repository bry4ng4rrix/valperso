"""Rôles et permissions. Les deux rôles (ADMIN, VENDEUR) sont fixes : seules leur description et
leurs permissions se modifient."""

from collections.abc import Iterable

from sqlalchemy.orm import Session

from app.core.exceptions import BusinessRuleError, NotFoundError
from app.core.permissions import ADMIN_REQUIRED_PERMISSIONS, RoleName
from app.models import Permission, Role, User
from app.repositories import role_repository
from app.schemas.role import RolePermissionsUpdate, RoleRead, RoleUpdate
from app.services import audit_service


def list_roles(db: Session) -> list[Role]:
    return role_repository.list_roles(db)


def list_permissions(db: Session) -> list[Permission]:
    return role_repository.list_permissions(db)


def get_role(db: Session, role_id: int) -> Role:
    role = db.get(Role, role_id)
    if role is None:
        raise NotFoundError("Rôle introuvable")
    return role


def _get_permissions(db: Session, permission_ids: Iterable[int]) -> list[Permission]:
    wanted = set(permission_ids)
    permissions = role_repository.get_permissions_by_ids(db, wanted)
    missing = wanted - {permission.id for permission in permissions}
    if missing:
        raise NotFoundError(f"Permissions introuvables : {sorted(missing)}")
    return permissions


def _save_role_change(
    db: Session, actor: User, role: Role, action: str, old_data: dict, ip_address: str | None
) -> Role:
    db.flush()
    audit_service.record(
        db,
        user_id=actor.id,
        action=action,
        entity_type="role",
        entity_id=role.id,
        old_data=old_data,
        new_data=audit_service.snapshot(RoleRead, role),
        ip_address=ip_address,
    )
    db.commit()
    return role


def update_role(db: Session, actor: User, role_id: int, data: RoleUpdate, ip_address: str | None = None) -> Role:
    role = get_role(db, role_id)
    old_data = audit_service.snapshot(RoleRead, role)
    role.description = data.description
    return _save_role_change(db, actor, role, "role.update", old_data, ip_address)


def set_role_permissions(
    db: Session, actor: User, role_id: int, data: RolePermissionsUpdate, ip_address: str | None = None
) -> Role:
    """Remplace la liste complète des permissions d'un rôle."""
    role = get_role(db, role_id)
    permissions = _get_permissions(db, data.permission_ids)
    if role.name == RoleName.ADMIN:
        missing = {code.value for code in ADMIN_REQUIRED_PERMISSIONS} - {p.name for p in permissions}
        if missing:
            raise BusinessRuleError(
                f"Le rôle ADMIN doit conserver : {', '.join(sorted(missing))} "
                "(sinon plus personne ne pourrait gérer les permissions)"
            )

    old_data = audit_service.snapshot(RoleRead, role)
    role.permissions = permissions
    return _save_role_change(db, actor, role, "role.permissions_update", old_data, ip_address)
