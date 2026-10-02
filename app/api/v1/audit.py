from typing import Annotated

from fastapi import APIRouter, Query

from app.api.responses import PROTECTED, error_responses
from app.core.deps import DbSession, require_permission
from app.core.permissions import PermissionCode as P
from app.models import User
from app.schemas.audit import AuditFilters, AuditLogRead
from app.schemas.common import Page
from app.services import audit_service

router = APIRouter(prefix="/audit", tags=["Audit"], responses=PROTECTED)


@router.get("", response_model=Page[AuditLogRead], summary="Consulter le journal d'audit")
def list_logs(
    db: DbSession,
    filters: Annotated[AuditFilters, Query()],
    _: Annotated[User, require_permission(P.AUDIT_VIEW)],
):
    """Filtrer par utilisateur, action (ex. `sale.create`), type d'entité (ex. `product`) ou période."""
    return audit_service.list_logs(db, filters)


@router.get(
    "/{log_id}", response_model=AuditLogRead, summary="Détail d'une entrée", responses=error_responses(404)
)
def get_log(log_id: int, db: DbSession, _: Annotated[User, require_permission(P.AUDIT_VIEW)]):
    return audit_service.get_log(db, log_id)
