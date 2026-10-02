from typing import Annotated

from fastapi import APIRouter, Query, status

from app.api.responses import PROTECTED, error_responses
from app.core.deps import ClientIP, DbSession, require_permission
from app.core.permissions import PermissionCode as P
from app.models import User
from app.schemas.common import Page
from app.schemas.payment import PaymentCreate, PaymentFilters, PaymentRead
from app.services import payment_service

router = APIRouter(prefix="/payments", tags=["Paiements"], responses=PROTECTED)


@router.get("", response_model=Page[PaymentRead], summary="Lister les paiements")
def list_payments(
    db: DbSession,
    filters: Annotated[PaymentFilters, Query()],
    current_user: Annotated[User, require_permission(P.PAYMENT_VIEW)],
):
    """Tri possible : `created_at`, `amount`."""
    return payment_service.list_payments(db, current_user, filters)


@router.get(
    "/{payment_id}",
    response_model=PaymentRead,
    summary="Détail d'un paiement",
    responses=error_responses(404),
)
def get_payment(
    payment_id: int, db: DbSession, current_user: Annotated[User, require_permission(P.PAYMENT_VIEW)]
):
    return payment_service.get_payment(db, current_user, payment_id)


@router.post(
    "",
    response_model=PaymentRead,
    status_code=status.HTTP_201_CREATED,
    summary="Enregistrer un règlement",
    responses=error_responses(400, 404),
)
def create_payment(
    data: PaymentCreate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.PAYMENT_CREATE)],
):
    """Règle tout ou partie du reste à payer d'une vente (ex. vente faite à CREDIT).
    Le montant ne peut pas dépasser le reste à payer. Un règlement en espèces entre dans la caisse."""
    return payment_service.add_payment(db, current_user, data, ip_address)
