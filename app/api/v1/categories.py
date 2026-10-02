from typing import Annotated

from fastapi import APIRouter, Query, status

from app.api.responses import PROTECTED, error_responses
from app.core.dependencies import ClientIP, DbSession, require_permission
from app.core.permissions import PermissionCode as P
from app.models import User
from app.schemas.category import CategoryCreate, CategoryFilters, CategoryRead, CategoryUpdate
from app.schemas.common import Page
from app.services import category_service

router = APIRouter(prefix="/categories", tags=["Catégories"], responses=PROTECTED)


@router.get("", response_model=Page[CategoryRead], summary="Lister les catégories")
def list_categories(
    db: DbSession,
    filters: Annotated[CategoryFilters, Query()],
    _: Annotated[User, require_permission(P.PRODUCT_VIEW)],
):
    """Tri possible : `name`, `created_at`."""
    return category_service.list_categories(db, filters)


@router.get(
    "/{category_id}",
    response_model=CategoryRead,
    summary="Détail d'une catégorie",
    responses=error_responses(404),
)
def get_category(category_id: int, db: DbSession, _: Annotated[User, require_permission(P.PRODUCT_VIEW)]):
    return category_service.get_category(db, category_id)


@router.post(
    "",
    response_model=CategoryRead,
    status_code=status.HTTP_201_CREATED,
    summary="Créer une catégorie",
    responses=error_responses(409),
)
def create_category(
    data: CategoryCreate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.PRODUCT_CREATE)],
):
    return category_service.create_category(db, current_user, data, ip_address)


@router.patch(
    "/{category_id}",
    response_model=CategoryRead,
    summary="Modifier une catégorie",
    responses=error_responses(404, 409),
)
def update_category(
    category_id: int,
    data: CategoryUpdate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.PRODUCT_UPDATE)],
):
    return category_service.update_category(db, current_user, category_id, data, ip_address)


@router.delete(
    "/{category_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Désactiver une catégorie",
    responses=error_responses(404),
)
def delete_category(
    category_id: int,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.PRODUCT_DELETE)],
) -> None:
    """Suppression logique : la catégorie est désactivée, ses produits sont conservés."""
    category_service.delete_category(db, current_user, category_id, ip_address)
