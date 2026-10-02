from typing import Annotated

from fastapi import APIRouter, Query, status

from app.api.responses import PROTECTED, error_responses
from app.core.dependencies import ClientIP, DbSession, require_permission
from app.core.permissions import PermissionCode as P
from app.models import User
from app.schemas.common import Page
from app.schemas.stock import (
    AlertThresholdUpdate,
    StockAdjustmentCreate,
    StockAlertFilters,
    StockEntryCreate,
    StockExitCreate,
    StockFilters,
    StockMovementFilters,
    StockMovementRead,
    StockRead,
)
from app.services import stock_service

router = APIRouter(prefix="/stock", tags=["Stock"], responses=PROTECTED)

STOCK_ERRORS = error_responses(400, 404)

# Les routes à chemin fixe (/low-stock, /movements...) sont déclarées avant /{stock_id}.


@router.get("", response_model=Page[StockRead], summary="Stock par magasin")
def list_stocks(
    db: DbSession,
    filters: Annotated[StockFilters, Query()],
    current_user: Annotated[User, require_permission(P.STOCK_VIEW)],
):
    """Une ligne par couple (produit, magasin). Un VENDEUR ne voit que son magasin.
    Filtres : `store_id`, `product_id`, `category_id`, `low_stock`, `out_of_stock`, `search`.
    Tri : `name`, `reference`, `quantity`, `updated_at`."""
    return stock_service.list_stocks(db, current_user, filters)


@router.get("/low-stock", response_model=Page[StockRead], summary="Stocks faibles")
def list_low_stock(
    db: DbSession,
    filters: Annotated[StockAlertFilters, Query()],
    current_user: Annotated[User, require_permission(P.STOCK_VIEW)],
):
    """Lignes dont la quantité est > 0 et inférieure ou égale au seuil d'alerte."""
    return stock_service.list_low_stock(db, current_user, filters)


@router.get("/out-of-stock", response_model=Page[StockRead], summary="Ruptures de stock")
def list_out_of_stock(
    db: DbSession,
    filters: Annotated[StockAlertFilters, Query()],
    current_user: Annotated[User, require_permission(P.STOCK_VIEW)],
):
    """Lignes à zéro dans un magasin (le produit peut être disponible dans un autre magasin)."""
    return stock_service.list_out_of_stock(db, current_user, filters)


@router.get(
    "/store/{store_id}",
    response_model=Page[StockRead],
    summary="Stock d'un magasin",
    responses=error_responses(404),
)
def list_store_stocks(
    store_id: int,
    db: DbSession,
    filters: Annotated[StockFilters, Query()],
    current_user: Annotated[User, require_permission(P.STORE_STOCK_VIEW)],
):
    """Un VENDEUR ne peut consulter que le stock de son propre magasin."""
    return stock_service.list_store_stocks(db, current_user, store_id, filters)


@router.get("/movements", response_model=Page[StockMovementRead], summary="Historique des mouvements")
def list_movements(
    db: DbSession,
    filters: Annotated[StockMovementFilters, Query()],
    current_user: Annotated[User, require_permission(P.STOCK_VIEW)],
):
    """Quantité positive = entrée en stock, négative = sortie. Tri : `created_at`, `quantity`."""
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
    """Mouvement de stock : utilisateur, magasin, produit, quantité signée, motif, référence."""
    return stock_service.get_movement(db, current_user, movement_id)


@router.get(
    "/{stock_id}",
    response_model=StockRead,
    summary="Détail d'une ligne de stock",
    responses=error_responses(404),
)
def get_stock(stock_id: int, db: DbSession, current_user: Annotated[User, require_permission(P.STOCK_VIEW)]):
    """Ligne de stock avec ses états d'alerte et ses valeurs (stock, vente, bénéfice potentiel)."""
    return stock_service.get_stock(db, current_user, stock_id)


@router.put(
    "/{stock_id}/alert-threshold",
    response_model=StockRead,
    summary="Modifier le seuil d'alerte",
    responses=error_responses(404),
)
def update_alert_threshold(
    stock_id: int,
    data: AlertThresholdUpdate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.STOCK_ADJUST)],
):
    """Fixe le seuil d'alerte de cette ligne de stock (un VENDEUR : son magasin uniquement)."""
    return stock_service.update_alert_threshold(db, current_user, stock_id, data, ip_address)


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
    """Ajoute une quantité dans un magasin (par défaut le Stock Local pour un ADMIN).
    La ligne de stock est créée si le magasin n'avait pas encore le produit."""
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
    """Retire une quantité du stock d'un magasin.
    Erreur 400 (INSUFFICIENT_STOCK) si le stock est insuffisant."""
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
    """Fixe la quantité d'un produit dans un magasin à la valeur réellement comptée (motif obligatoire)."""
    return stock_service.adjust_stock(db, current_user, data, ip_address)
