from typing import Annotated

from fastapi import APIRouter, File, Query, UploadFile, status

from app.api.responses import PROTECTED, error_responses
from app.core.dependencies import ClientIP, DbSession, require_permission
from app.core.permissions import PermissionCode as P
from app.models import User
from app.schemas.common import Page
from app.schemas.product import ProductCreate, ProductFilters, ProductRead, ProductUpdate
from app.services import product_image_service, product_service

router = APIRouter(prefix="/products", tags=["Produits"], responses=PROTECTED)


@router.get("", response_model=Page[ProductRead], summary="Lister les produits")
def list_products(
    db: DbSession,
    filters: Annotated[ProductFilters, Query()],
    _: Annotated[User, require_permission(P.PRODUCT_VIEW)],
):
    """Recherche sur la référence ou le nom (insensible à la casse).
    La référence et le nom ne sont pas uniques. Tri : `name`, `reference`, `selling_price`, `created_at`."""
    return product_service.list_products(db, filters)


@router.get(
    "/{product_id}", response_model=ProductRead, summary="Détail d'un produit", responses=error_responses(404)
)
def get_product(product_id: int, db: DbSession, _: Annotated[User, require_permission(P.PRODUCT_VIEW)]):
    """Retourne le produit, sa catégorie et son bénéfice unitaire."""
    return product_service.get_product(db, product_id)


@router.post(
    "",
    response_model=ProductRead,
    status_code=status.HTTP_201_CREATED,
    summary="Créer un produit",
    responses=error_responses(400, 404),
)
def create_product(
    data: ProductCreate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.PRODUCT_CREATE)],
):
    """Crée le produit et sa ligne de stock à 0 dans le Stock Local. Pour l'approvisionner :
    `POST /api/v1/stock/entry`. Référence et nom peuvent être identiques à ceux d'un autre produit."""
    return product_service.create_product(db, current_user, data, ip_address)


@router.patch(
    "/{product_id}",
    response_model=ProductRead,
    summary="Modifier un produit",
    responses=error_responses(400, 404),
)
def update_product(
    product_id: int,
    data: ProductUpdate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.PRODUCT_UPDATE)],
):
    """Le stock ne se modifie pas ici mais via les opérations de stock."""
    return product_service.update_product(db, current_user, product_id, data, ip_address)


@router.delete(
    "/{product_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Désactiver un produit",
    responses=error_responses(404),
)
def delete_product(
    product_id: int,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.PRODUCT_DELETE)],
) -> None:
    """Suppression logique : le produit devient non vendable, son historique est conservé."""
    product_service.delete_product(db, current_user, product_id, ip_address)


@router.post(
    "/{product_id}/images",
    response_model=ProductRead,
    status_code=status.HTTP_201_CREATED,
    summary="Ajouter une photo",
    responses=error_responses(400, 404),
)
def add_product_image(
    product_id: int,
    file: Annotated[UploadFile, File(description="Photo JPEG, PNG ou WebP (5 Mo maximum)")],
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.PRODUCT_UPDATE)],
):
    """Ajoute une photo au produit (10 au maximum). La première photo est la photo principale.
    Le fichier est servi ensuite à l'adresse indiquée dans `images[].url` (/media/...)."""
    content = file.file.read(product_image_service.MAX_IMAGE_BYTES + 1)
    return product_image_service.add_image(db, current_user, product_id, content, ip_address)


@router.delete(
    "/{product_id}/images/{image_id}",
    response_model=ProductRead,
    summary="Supprimer une photo",
    responses=error_responses(404),
)
def delete_product_image(
    product_id: int,
    image_id: int,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.PRODUCT_UPDATE)],
):
    """Supprime la photo et son fichier."""
    return product_image_service.delete_image(db, current_user, product_id, image_id, ip_address)
