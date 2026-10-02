from typing import Annotated

from fastapi import APIRouter

from app.api.responses import PROTECTED
from app.core.dependencies import ClientIP, DbSession, require_permission
from app.core.permissions import PermissionCode as P
from app.models import User
from app.schemas.company import CompanyRead, CompanyUpdate
from app.services import company_service

router = APIRouter(prefix="/company", tags=["Société"], responses=PROTECTED)


@router.get("", response_model=CompanyRead, summary="Informations de la société")
def get_company(db: DbSession, _: Annotated[User, require_permission(P.COMPANY_VIEW)]):
    """Nom, logo, téléphone, email, adresse et ville affichés en en-tête des factures."""
    return company_service.get_company(db)


@router.put("", response_model=CompanyRead, summary="Modifier les informations de la société")
def update_company(
    data: CompanyUpdate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.COMPANY_UPDATE)],
):
    """Réservé à l'ADMIN (permission `company.update`), tracé dans l'audit (ancienne et nouvelle valeur).
    Les nouvelles factures utilisent ces informations ; les factures déjà émises ne changent pas.
    `logo_url` : adresse web (https://...) ou chemin (/media/logo.png) du logo, remplaçable à tout moment."""
    return company_service.update_company(db, current_user, data, ip_address)
