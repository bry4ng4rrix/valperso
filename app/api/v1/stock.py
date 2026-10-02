from typing import Annotated

from fastapi import APIRouter, Query, status

from app.api.responses import PROTECTED, error_responses
from app.core.deps import ClientIP, DbSession, require_permission
from app.core.permissions import PermissionCode as P
from app.models import User
from app.schemas.common import Page
from app.schemas.stock import (
    StockAdjustmentCreate,
    StockEntryCreate,
    StockExitCreate,
    StockMovementFilters,
    StockMovementRead,
    StockTransferCreate,
    StockTransferFilters,
    StockTransferRead,
    StockTransferResult,
)
from app.services import stock_service, transfer_service

router = APIRouter(prefix="/stock", tags=["Stock"], responses=PROTECTED)

STOCK_ERRORS = error_responses(400, 404)


# --- Mouvements ----------------------------------------------------------------------------------


@router.get(
    "/movements", response_model=Page[StockMovementRead], summary="Historique des mouvements de stock"
)
def list_movements(
    db: DbSession,
    filters: Annotated[StockMovementFilters, Query()],
    current_user: Annotated[User, require_permission(P.STOCK_VIEW)],
):
    """Quantité positive = entrée en stock, négative = sortie. Tri possible : `created_at`, `quantity`."""
    return stock_service.list_movements(db, current_user, filters)


@router.get(
    "/movements/{movement_id}",
    response_model=StockMovementRead,
    summary="Détail d'un mouvement",
    responses=error_responses(404),
)
def get_movement(
    movement_id: int, db: DbSession, current_user: Annotated[User, require_permission(P.STOCK_VIEW)]
):
    return stock_service.get_movement(db, current_user, movement_id)


@router.post(
    "/entry",
    response_model=StockMovementRead,
    status_code=status.HTTP_201_CREATED,
    summary="Entrée de stock",
    responses=STOCK_ERRORS,
)
def stock_entry(
    data: StockEntryCreate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.STOCK_ENTRY)],
):
    """Ajoute une quantité dans un magasin (par défaut le magasin de l'utilisateur, sinon le STOCK LOCAL).
    L'article est créé dans le magasin s'il n'y existait pas encore."""
    return stock_service.record_entry(db, current_user, data, ip_address)


@router.post(
    "/exit",
    response_model=StockMovementRead,
    status_code=status.HTTP_201_CREATED,
    summary="Sortie ou perte de stock",
    responses=STOCK_ERRORS,
)
def stock_exit(
    data: StockExitCreate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.STOCK_EXIT)],
):
    """Retire une quantité du stock d'un magasin. Erreur 400 si le stock est insuffisant."""
    return stock_service.record_exit(db, current_user, data, ip_address)


@router.post(
    "/adjust",
    response_model=StockMovementRead,
    status_code=status.HTTP_201_CREATED,
    summary="Ajustement d'inventaire",
    responses=STOCK_ERRORS,
)
def stock_adjust(
    data: StockAdjustmentCreate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.STOCK_ADJUST)],
):
    """Fixe la quantité d'un article dans un magasin à la valeur réellement comptée (motif obligatoire)."""
    return stock_service.adjust_stock(db, current_user, data, ip_address)


# --- Transferts entre magasins -------------------------------------------------------------------


@router.post(
    "/transfers",
    response_model=StockTransferResult,
    status_code=status.HTTP_201_CREATED,
    summary="Transférer un produit vers un autre magasin",
    responses=STOCK_ERRORS,
)
def create_transfer(
    data: StockTransferCreate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.STOCK_TRANSFER)],
):
    """Déplace une quantité d'un produit du magasin source (par défaut le STOCK LOCAL) vers un autre magasin.

    - Transfert partiel (ex. 5 sur 10) : l'article est créé dans le magasin de destination s'il n'y
      existait pas, et la quantité du magasin source diminue.
    - Transfert total (10 sur 10) : tout est déplacé et l'article passe en **RUPTURE** dans le magasin source.

    La réponse contient le transfert et l'état du stock dans les deux magasins.
    """
    return transfer_service.transfer_stock(db, current_user, data, ip_address)


@router.get("/transfers", response_model=Page[StockTransferRead], summary="Historique des transferts")
def list_transfers(
    db: DbSession,
    filters: Annotated[StockTransferFilters, Query()],
    current_user: Annotated[User, require_permission(P.STOCK_VIEW)],
):
    """Tri possible : `created_at`, `quantity`."""
    return transfer_service.list_transfers(db, current_user, filters)


@router.get(
    "/transfers/{transfer_id}",
    response_model=StockTransferRead,
    summary="Détail d'un transfert",
    responses=error_responses(404),
)
def get_transfer(
    transfer_id: int, db: DbSession, current_user: Annotated[User, require_permission(P.STOCK_VIEW)]
):
    return transfer_service.get_transfer(db, current_user, transfer_id)
