from collections.abc import Iterable

from sqlalchemy.orm import Session

from app.core.exceptions import BusinessRuleError, ConflictError, NotFoundError
from app.core.permissions import RoleName
from app.models import Permission, Role, User
from app.repositories import role_repository
from app.schemas.role import RoleCreate, RolePermissionsUpdate, RoleRead, RoleUpdate
from app.services import audit_service
from app.utils.text import display_text

SYSTEM_ROLES = {role.value for role in RoleName}


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


def _ensure_unique_name(db: Session, name: str) -> None:
    if role_repository.get_by_name(db, name) is not None:
        raise ConflictError(f"Le rôle « {display_text(name)} » existe déjà")


def create_role(db: Session, actor: User, data: RoleCreate, ip_address: str | None = None) -> Role:
    _ensure_unique_name(db, data.name)
    role = Role(
        name=data.name,
        description=data.description,
        permissions=_get_permissions(db, data.permission_ids),
    )
    db.add(role)
    db.flush()
    audit_service.record(
        db,
        user_id=actor.id,
        action="role.create",
        entity_type="role",
        entity_id=role.id,
        new_data=audit_service.snapshot(RoleRead, role),
        ip_address=ip_address,
    )
    db.commit()
    return role


def update_role(
    db: Session, actor: User, role_id: int, data: RoleUpdate, ip_address: str | None = None
) -> Role:
    role = get_role(db, role_id)
    changes = data.changes()
    if "name" in changes and changes["name"] != role.name:
        if role.name in SYSTEM_ROLES:
            raise BusinessRuleError("Un rôle système ne peut pas être renommé")
        _ensure_unique_name(db, changes["name"])

    old_data = audit_service.snapshot(RoleRead, role)
    for field, value in changes.items():
        setattr(role, field, value)
    db.flush()
    audit_service.record(
        db,
        user_id=actor.id,
        action="role.update",
        entity_type="role",
        entity_id=role.id,
        old_data=old_data,
        new_data=audit_service.snapshot(RoleRead, role),
        ip_address=ip_address,
    )
    db.commit()
    return role


def set_role_permissions(
    db: Session, actor: User, role_id: int, data: RolePermissionsUpdate, ip_address: str | None = None
) -> Role:
    """Remplace la liste complète des permissions d'un rôle."""
    role = get_role(db, role_id)
    if role.name == RoleName.ADMIN:
        raise BusinessRuleError("Le rôle ADMIN possède toujours toutes les permissions")

    old_data = audit_service.snapshot(RoleRead, role)
    role.permissions = _get_permissions(db, data.permission_ids)
    db.flush()
    audit_service.record(
        db,
        user_id=actor.id,
        action="role.permissions_update",
        entity_type="role",
        entity_id=role.id,
        old_data=old_data,
        new_data=audit_service.snapshot(RoleRead, role),
        ip_address=ip_address,
    )
    db.commit()
    return role


def delete_role(db: Session, actor: User, role_id: int, ip_address: str | None = None) -> None:
    role = get_role(db, role_id)
    if role.name in SYSTEM_ROLES:
        raise BusinessRuleError("Un rôle système ne peut pas être supprimé")
    if role_repository.count_users(db, role.id) > 0:
        raise BusinessRuleError(
            "Ce rôle est attribué à des utilisateurs : réaffectez-les avant de le supprimer"
        )

    old_data = audit_service.snapshot(RoleRead, role)
    db.delete(role)
    audit_service.record(
        db,
        user_id=actor.id,
        action="role.delete",
        entity_type="role",
        entity_id=role_id,
        old_data=old_data,
        ip_address=ip_address,
    )
    db.commit()
