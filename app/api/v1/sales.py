from typing import Annotated

from fastapi import APIRouter, Query, status

from app.api.responses import PROTECTED, error_responses
from app.core.deps import ClientIP, DbSession, require_permission
from app.core.permissions import PermissionCode as P
from app.models import User
from app.schemas.common import Page
from app.schemas.sale import SaleCancel, SaleCreate, SaleFilters, SaleRead, SaleSummary
from app.services import sale_service

router = APIRouter(prefix="/sales", tags=["Ventes"], responses=PROTECTED)


@router.get("", response_model=Page[SaleSummary], summary="Lister les ventes")
def list_sales(
    db: DbSession,
    filters: Annotated[SaleFilters, Query()],
    current_user: Annotated[User, require_permission(P.SALE_VIEW)],
):
    """Un utilisateur rattaché à un magasin ne voit que les ventes de ce magasin.
    Tri possible : `created_at`, `total`, `sale_number`."""
    return sale_service.list_sales(db, current_user, filters)


@router.get(
    "/{sale_id}",
    response_model=SaleRead,
    summary="Détail d'une vente (lignes et paiements)",
    responses=error_responses(404),
)
def get_sale(sale_id: int, db: DbSession, current_user: Annotated[User, require_permission(P.SALE_VIEW)]):
    return sale_service.get_sale(db, current_user, sale_id)


@router.post(
    "",
    response_model=SaleRead,
    status_code=status.HTTP_201_CREATED,
    summary="Créer une vente",
    responses=error_responses(400, 404),
)
def create_sale(
    data: SaleCreate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.SALE_CREATE)],
):
    """Enregistre une vente complète dans une seule transaction : lignes, déduction du stock du magasin,
    mouvements de stock, paiement, caisse (si espèces) et audit. En cas d'erreur, rien n'est enregistré.

    - Les prix et totaux sont **calculés par le serveur** à partir des prix des produits.
    - `customer_name` est facultatif (il n'y a pas de fiche client).
    - Une réduction (`PERCENTAGE` ou `FIXED`) nécessite la permission `sale.discount`.
    - Un paiement `CASH` nécessite une caisse ouverte dans le magasin.
    - Un paiement `CREDIT` laisse le total dû ; il se règle ensuite via `POST /api/v1/payments`.
    """
    return sale_service.create_sale(db, current_user, data, ip_address)


@router.post(
    "/{sale_id}/cancel",
    response_model=SaleRead,
    summary="Annuler une vente",
    responses=error_responses(400, 404),
)
def cancel_sale(
    sale_id: int,
    data: SaleCancel,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.SALE_CANCEL)],
):
    """Remet les quantités dans le stock du magasin (mouvements RETURN) et rembourse les espèces
    encaissées depuis la caisse ouverte."""
    return sale_service.cancel_sale(db, current_user, sale_id, data, ip_address)
