from typing import Annotated

from fastapi import APIRouter

from app.api.responses import PROTECTED
from app.core.dependencies import DbSession, require_permission
from app.core.permissions import PermissionCode as P
from app.models import User
from app.schemas.role import PermissionRead
from app.services import role_service

router = APIRouter(prefix="/permissions", tags=["Rôles et permissions"], responses=PROTECTED)


@router.get("", response_model=list[PermissionRead], summary="Lister les permissions disponibles")
def list_permissions(db: DbSession, _: Annotated[User, require_permission(P.PERMISSION_VIEW)]):
    """Les permissions sont définies par l'application (script de seed) : elles sont en lecture seule.
    Elles s'attribuent aux rôles avec `PUT /api/v1/roles/{id}/permissions`."""
    return role_service.list_permissions(db)
