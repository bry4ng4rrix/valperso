from typing import Annotated

from fastapi import APIRouter

from app.api.responses import PROTECTED, error_responses
from app.core.dependencies import ClientIP, DbSession, require_permission
from app.core.permissions import PermissionCode as P
from app.models import User
from app.schemas.role import RolePermissionsUpdate, RoleRead, RoleUpdate
from app.services import role_service

router = APIRouter(prefix="/roles", tags=["Rôles et permissions"], responses=PROTECTED)


@router.get("", response_model=list[RoleRead], summary="Lister les rôles et leurs permissions")
def list_roles(db: DbSession, _: Annotated[User, require_permission(P.ROLE_VIEW)]):
    """Il n'existe que deux rôles : ADMIN et VENDEUR."""
    return role_service.list_roles(db)


@router.get("/{role_id}", response_model=RoleRead, summary="Détail d'un rôle", responses=error_responses(404))
def get_role(role_id: int, db: DbSession, _: Annotated[User, require_permission(P.ROLE_VIEW)]):
    return role_service.get_role(db, role_id)


@router.put("/{role_id}", response_model=RoleRead, summary="Modifier un rôle", responses=error_responses(404))
def update_role(
    role_id: int,
    data: RoleUpdate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.ROLE_UPDATE)],
):
    """Seule la description est modifiable : les rôles ADMIN et VENDEUR sont fixes."""
    return role_service.update_role(db, current_user, role_id, data, ip_address)


@router.put(
    "/{role_id}/permissions",
    response_model=RoleRead,
    summary="Attribuer les permissions d'un rôle",
    responses=error_responses(400, 404),
)
def set_role_permissions(
    role_id: int,
    data: RolePermissionsUpdate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.PERMISSION_ASSIGN)],
):
    """Remplace la liste complète des permissions du rôle. Le rôle ADMIN doit garder
    `permission.view`, `permission.assign` et `role.view`."""
    return role_service.set_role_permissions(db, current_user, role_id, data, ip_address)
