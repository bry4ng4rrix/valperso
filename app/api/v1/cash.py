from typing import Annotated

from fastapi import APIRouter, Query, status

from app.api.responses import PROTECTED, error_responses
from app.core.dependencies import ClientIP, DbSession, require_permission
from app.core.permissions import PermissionCode as P
from app.models import User
from app.schemas.cash import (
    CashRegisterClose,
    CashRegisterFilters,
    CashRegisterOpen,
    CashRegisterRead,
    CashTransactionCreate,
    CashTransactionRead,
)
from app.schemas.common import Page, Pagination
from app.services import cash_service

router = APIRouter(prefix="/cash", tags=["Caisse"], responses=PROTECTED)


@router.get("/registers", response_model=Page[CashRegisterRead], summary="Lister les caisses")
def list_registers(
    db: DbSession,
    filters: Annotated[CashRegisterFilters, Query()],
    current_user: Annotated[User, require_permission(P.CASH_VIEW)],
):
    """Tri possible : `opened_at`, `closed_at`."""
    return cash_service.list_registers(db, current_user, filters)


# Déclarée avant /registers/{register_id} pour que "current" ne soit pas lu comme un identifiant.
@router.get(
    "/registers/current",
    response_model=CashRegisterRead,
    summary="Caisse ouverte d'un magasin",
    responses=error_responses(400, 404),
)
def get_current_register(
    db: DbSession,
    current_user: Annotated[User, require_permission(P.CASH_VIEW)],
    store_id: Annotated[int | None, Query(gt=0)] = None,
):
    """Par défaut : le magasin de l'utilisateur, sinon le STOCK LOCAL."""
    return cash_service.get_current_register(db, current_user, store_id)


@router.get(
    "/registers/{register_id}",
    response_model=CashRegisterRead,
    summary="Détail d'une caisse",
    responses=error_responses(404),
)
def get_register(
    register_id: int, db: DbSession, current_user: Annotated[User, require_permission(P.CASH_VIEW)]
):
    """Retourne une caisse et son montant théorique (expected_amount)."""
    return cash_service.get_register(db, current_user, register_id)


@router.post(
    "/registers/open",
    response_model=CashRegisterRead,
    status_code=status.HTTP_201_CREATED,
    summary="Ouvrir une caisse",
    responses=error_responses(400, 404),
)
def open_register(
    data: CashRegisterOpen,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.CASH_OPEN)],
):
    """Une seule caisse peut être ouverte à la fois par magasin."""
    return cash_service.open_register(db, current_user, data, ip_address)


@router.post(
    "/registers/{register_id}/close",
    response_model=CashRegisterRead,
    summary="Clôturer une caisse",
    responses=error_responses(400, 404),
)
def close_register(
    register_id: int,
    data: CashRegisterClose,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.CASH_CLOSE)],
):
    """Enregistre le montant compté et calcule l'écart : `difference = closing_amount - expected_amount`."""
    return cash_service.close_register(db, current_user, register_id, data, ip_address)


@router.get(
    "/registers/{register_id}/transactions",
    response_model=Page[CashTransactionRead],
    summary="Opérations d'une caisse",
    responses=error_responses(404),
)
def list_transactions(
    register_id: int,
    db: DbSession,
    pagination: Annotated[Pagination, Query()],
    current_user: Annotated[User, require_permission(P.CASH_VIEW)],
):
    """Les plus récentes d'abord. Montant positif = entrée d'argent, négatif = sortie."""
    return cash_service.list_transactions(db, current_user, register_id, pagination)


@router.post(
    "/registers/{register_id}/transactions",
    response_model=CashTransactionRead,
    status_code=status.HTTP_201_CREATED,
    summary="Enregistrer une opération de caisse",
    responses=error_responses(400, 404),
)
def add_transaction(
    register_id: int,
    data: CashTransactionCreate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.CASH_TRANSACTION)],
):
    """Dépense (EXPENSE), retrait (WITHDRAWAL), dépôt (DEPOSIT) ou ajustement (ADJUSTMENT).
    Les opérations SALE et REFUND sont créées automatiquement par les ventes."""
    return cash_service.add_manual_transaction(db, current_user, register_id, data, ip_address)
