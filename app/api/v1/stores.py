from typing import Annotated

from fastapi import APIRouter, Query, status

from app.api.responses import PROTECTED, error_responses
from app.core.deps import ClientIP, DbSession, require_permission
from app.core.permissions import PermissionCode as P
from app.models import User
from app.schemas.common import Page
from app.schemas.stock import StoreStockFilters, StoreStockRead
from app.schemas.store import StoreCreate, StoreFilters, StoreRead, StoreUpdate
from app.services import stock_service, store_service

router = APIRouter(prefix="/stores", tags=["Magasins"], responses=PROTECTED)


@router.get("", response_model=Page[StoreRead], summary="Lister les magasins")
def list_stores(
    db: DbSession,
    filters: Annotated[StoreFilters, Query()],
    _: Annotated[User, require_permission(P.STORE_VIEW)],
):
    """Le STOCK LOCAL (magasin par défaut) apparaît en premier. Tri possible : `name`, `created_at`."""
    return store_service.list_stores(db, filters)


@router.get(
    "/{store_id}", response_model=StoreRead, summary="Détail d'un magasin", responses=error_responses(404)
)
def get_store(store_id: int, db: DbSession, _: Annotated[User, require_permission(P.STORE_VIEW)]):
    return store_service.get_store(db, store_id)


@router.get(
    "/{store_id}/stock",
    response_model=Page[StoreStockRead],
    summary="Stock d'un magasin",
    responses=error_responses(404),
)
def list_store_stock(
    store_id: int,
    db: DbSession,
    filters: Annotated[StoreStockFilters, Query()],
    current_user: Annotated[User, require_permission(P.STOCK_VIEW)],
):
    """Articles présents dans le magasin avec leur quantité et leur statut :
    `EN_STOCK`, `STOCK_FAIBLE` ou `RUPTURE`. Tri possible : `name`, `reference`, `quantity`, `updated_at`."""
    return stock_service.list_store_stock(db, current_user, store_id, filters)


@router.post(
    "",
    response_model=StoreRead,
    status_code=status.HTTP_201_CREATED,
    summary="Créer un magasin",
    responses=error_responses(409),
)
def create_store(
    data: StoreCreate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.STORE_CREATE)],
):
    return store_service.create_store(db, current_user, data, ip_address)


@router.patch(
    "/{store_id}",
    response_model=StoreRead,
    summary="Modifier un magasin",
    responses=error_responses(400, 404, 409),
)
def update_store(
    store_id: int,
    data: StoreUpdate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.STORE_UPDATE)],
):
    return store_service.update_store(db, current_user, store_id, data, ip_address)


@router.delete(
    "/{store_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Désactiver un magasin",
    responses=error_responses(400, 404),
)
def delete_store(
    store_id: int,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.STORE_DELETE)],
) -> None:
    """Suppression logique. Le STOCK LOCAL ne peut pas être supprimé."""
    store_service.delete_store(db, current_user, store_id, ip_address)
