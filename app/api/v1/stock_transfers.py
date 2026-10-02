from typing import Annotated

from fastapi import APIRouter, Query, status

from app.api.responses import PROTECTED, error_responses
from app.core.dependencies import ClientIP, DbSession, require_any_permission, require_permission
from app.core.permissions import PermissionCode as P
from app.models import User
from app.schemas.common import Page
from app.schemas.stock_transfer import (
    StockTransferCreate,
    StockTransferFilters,
    StockTransferRead,
    StockTransferResult,
)
from app.services import stock_transfer_service

router = APIRouter(prefix="/stock-transfers", tags=["Transferts"], responses=PROTECTED)


@router.get("", response_model=Page[StockTransferRead], summary="Historique des transferts")
def list_transfers(
    db: DbSession,
    filters: Annotated[StockTransferFilters, Query()],
    current_user: Annotated[User, require_permission(P.STORE_TRANSFER_VIEW)],
):
    """Un VENDEUR ne voit que les transferts envoyés ou reçus par son magasin.
    Tri : `created_at`, `reference`."""
    return stock_transfer_service.list_transfers(db, current_user, filters)


@router.post(
    "",
    response_model=StockTransferResult,
    status_code=status.HTTP_201_CREATED,
    summary="Transférer du stock vers un autre magasin",
    responses=error_responses(400, 404),
)
def create_transfer(
    data: StockTransferCreate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_any_permission(P.STORE_TRANSFER_CREATE, P.STOCK_TRANSFER)],
):
    """Déplace des quantités du magasin source (par défaut le Stock Local) vers le magasin destination.

    - 10 en stock, transfert de 5 : source 5, destination 5 (ligne créée si besoin).
    - 10 en stock, transfert de 10 : source 0 (stock **déplacé**, pas perdu), destination 10.
    - 10 en stock, transfert de 11 : refusé, rien n'est modifié.

    Le stock global ne change pas. Le transfert est atomique : tout est enregistré, ou rien.
    La réponse indique le stock de chaque produit dans les deux magasins après le transfert.
    """
    return stock_transfer_service.create_transfer(db, current_user, data, ip_address)


@router.get(
    "/{transfer_id}",
    response_model=StockTransferRead,
    summary="Détail d'un transfert",
    responses=error_responses(404),
)
def get_transfer(
    transfer_id: int, db: DbSession, current_user: Annotated[User, require_permission(P.STORE_TRANSFER_VIEW)]
):
    """Un VENDEUR ne peut consulter que les transferts qui concernent son magasin."""
    return stock_transfer_service.get_transfer(db, current_user, transfer_id)


@router.post(
    "/{transfer_id}/cancel",
    response_model=StockTransferResult,
    summary="Annuler un transfert",
    responses=error_responses(400, 404),
)
def cancel_transfer(
    transfer_id: int,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.STORE_TRANSFER_CANCEL)],
):
    """Renvoie les quantités de la destination vers la source. Impossible si la destination
    n'a plus assez de stock (déjà vendu ou transféré)."""
    return stock_transfer_service.cancel_transfer(db, current_user, transfer_id, ip_address)
