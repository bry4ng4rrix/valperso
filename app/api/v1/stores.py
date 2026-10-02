from typing import Annotated

from fastapi import APIRouter, Query, status

from app.api.responses import PROTECTED, error_responses
from app.core.dependencies import ClientIP, DbSession, require_permission
from app.core.permissions import PermissionCode as P
from app.models import User
from app.schemas.common import Page, Pagination
from app.schemas.store import StoreCreate, StoreFilters, StoreRead, StoreUpdate
from app.schemas.user import UserRead
from app.services import store_access, store_service, user_service

router = APIRouter(prefix="/stores", tags=["Magasins"], responses=PROTECTED)


@router.get("", response_model=Page[StoreRead], summary="Lister les magasins")
def list_stores(
    db: DbSession,
    filters: Annotated[StoreFilters, Query()],
    _: Annotated[User, require_permission(P.STORE_VIEW)],
):
    """Le Stock Local (stock central) apparaît en premier. Tri : `name`, `created_at`."""
    return store_service.list_stores(db, filters)


@router.get("/{store_id}", response_model=StoreRead, summary="Détail d'un magasin", responses=error_responses(404))
def get_store(store_id: int, db: DbSession, _: Annotated[User, require_permission(P.STORE_VIEW)]):
    return store_access.get_store(db, store_id)


@router.get(
    "/{store_id}/employees",
    response_model=Page[UserRead],
    summary="Employés affectés au magasin",
    responses=error_responses(404),
)
def list_employees(
    store_id: int,
    db: DbSession,
    pagination: Annotated[Pagination, Query()],
    _: Annotated[User, require_permission(P.USER_VIEW)],
):
    return user_service.list_store_employees(db, store_id, pagination)


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
    """Le magasin est créé sans vendeur. Les vendeurs y sont affectés ensuite
    avec `PUT /api/v1/users/{id}/store`."""
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
    """Modification partielle : seuls les champs envoyés changent. Le Stock Local ne peut pas être désactivé."""
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
    """Suppression logique : le magasin est désactivé, son historique et son stock sont conservés."""
    store_service.delete_store(db, current_user, store_id, ip_address)
