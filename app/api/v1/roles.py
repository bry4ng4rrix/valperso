from typing import Annotated

from fastapi import APIRouter, status

from app.api.responses import PROTECTED, error_responses
from app.core.deps import ClientIP, DbSession, require_permission
from app.core.permissions import PermissionCode as P
from app.models import User
from app.schemas.role import RoleCreate, RolePermissionsUpdate, RoleRead, RoleUpdate
from app.services import role_service

router = APIRouter(prefix="/roles", tags=["Rôles et permissions"], responses=PROTECTED)


@router.get("", response_model=list[RoleRead], summary="Lister les rôles et leurs permissions")
def list_roles(db: DbSession, _: Annotated[User, require_permission(P.ROLE_VIEW)]):
    return role_service.list_roles(db)


@router.get("/{role_id}", response_model=RoleRead, summary="Détail d'un rôle", responses=error_responses(404))
def get_role(role_id: int, db: DbSession, _: Annotated[User, require_permission(P.ROLE_VIEW)]):
    return role_service.get_role(db, role_id)


@router.post(
    "",
    response_model=RoleRead,
    status_code=status.HTTP_201_CREATED,
    summary="Créer un rôle",
    responses=error_responses(404, 409),
)
def create_role(
    data: RoleCreate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.ROLE_CREATE)],
):
    return role_service.create_role(db, current_user, data, ip_address)


@router.patch(
    "/{role_id}",
    response_model=RoleRead,
    summary="Modifier un rôle",
    responses=error_responses(400, 404, 409),
)
def update_role(
    role_id: int,
    data: RoleUpdate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.ROLE_UPDATE)],
):
    """Les rôles système (ADMIN, MANAGER, VENDEUR, CAISSIER, MAGASINIER) ne peuvent pas être renommés."""
    return role_service.update_role(db, current_user, role_id, data, ip_address)


@router.put(
    "/{role_id}/permissions",
    response_model=RoleRead,
    summary="Définir les permissions d'un rôle",
    responses=error_responses(400, 404),
)
def set_role_permissions(
    role_id: int,
    data: RolePermissionsUpdate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.ROLE_UPDATE)],
):
    """Remplace la liste complète des permissions du rôle. Le rôle ADMIN les possède toujours toutes."""
    return role_service.set_role_permissions(db, current_user, role_id, data, ip_address)


@router.delete(
    "/{role_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Supprimer un rôle",
    responses=error_responses(400, 404),
)
def delete_role(
    role_id: int,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.ROLE_DELETE)],
) -> None:
    """Impossible pour un rôle système ou un rôle encore attribué à des utilisateurs."""
    role_service.delete_role(db, current_user, role_id, ip_address)
