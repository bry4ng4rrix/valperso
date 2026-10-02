from typing import Annotated

from fastapi import APIRouter

from app.api.responses import PROTECTED, error_responses
from app.core.dependencies import DbSession, require_permission
from app.core.permissions import PermissionCode as P
from app.models import User
from app.schemas.invoice import InvoiceRead
from app.services import sale_service

router = APIRouter(prefix="/sales", tags=["Factures"], responses=PROTECTED)


@router.get(
    "/{sale_id}/invoice",
    response_model=InvoiceRead,
    summary="Facture d'une vente",
    responses=error_responses(404),
)
def get_invoice(sale_id: int, db: DbSession, current_user: Annotated[User, require_permission(P.SALE_VIEW)]):
    """Numéro, date, magasin, vendeur (et son rôle), client, lignes (références, quantités, prix
    unitaires), remise, total, paiements, montant payé, reste à payer, statut et échéance.
    Les lignes conservent le nom, la référence et le prix du produit au moment de la vente."""
    return sale_service.get_sale(db, current_user, sale_id)
