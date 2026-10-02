from typing import Annotated

from fastapi import APIRouter, Query, status

from app.api.responses import PROTECTED, error_responses
from app.core.dependencies import ClientIP, DbSession, require_permission
from app.core.permissions import PermissionCode as P
from app.models import User
from app.schemas.common import Page
from app.schemas.payment import PaymentRead
from app.schemas.sale import SaleCancel, SaleCreate, SaleHistoryFilters, SaleRead, SaleSummary
from app.services import sale_service

router = APIRouter(prefix="/sales", tags=["Ventes"], responses=PROTECTED)


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
    """Enregistre une vente complète en une seule transaction (lignes, stock, mouvements, paiement,
    audit). En cas d'erreur, rien n'est enregistré.

    - L'utilisateur responsable est **l'utilisateur connecté** ; un VENDEUR vend dans **son** magasin.
    - Client : `customer_id` (client existant) ou `customer` (nom, prénom, téléphone).
    - Prix, sous-total, remise et total sont calculés par le serveur. Remise : permission `sale.discount`.
    - Paiement : absent ou `CREDIT` = vente à crédit ; `amount` absent = paiement complet ;
      `amount` < total = avance. S'il reste un montant dû : téléphone du client obligatoire, et
      échéancier `installments` (dates et montants, somme = reste à payer) ou échéance unique
      `payment_due_date`.
    """
    return sale_service.create_sale(db, current_user, data, ip_address)


@router.get("/history", response_model=Page[SaleSummary], summary="Historique des ventes")
def list_history(
    db: DbSession,
    filters: Annotated[SaleHistoryFilters, Query()],
    current_user: Annotated[User, require_permission(P.SALE_VIEW)],
):
    """Recherche par n° de facture, nom, prénom ou téléphone du client (`search`), et filtres
    `user_id`, `store_id`, `customer_id`, `payment_status`, `has_debt`, `status`, `date_from`, `date_to`.
    Un VENDEUR ne voit que les ventes de son magasin. Tri : `created_at`, `total`, `sale_number`."""
    return sale_service.list_history(db, current_user, filters)


@router.get(
    "/{sale_id}",
    response_model=SaleRead,
    summary="Détail d'une vente",
    responses=error_responses(404),
)
def get_sale(sale_id: int, db: DbSession, current_user: Annotated[User, require_permission(P.SALE_VIEW)]):
    """Vente avec ses lignes, ses paiements, le montant payé et le reste à payer."""
    return sale_service.get_sale(db, current_user, sale_id)


@router.get(
    "/{sale_id}/payments",
    response_model=list[PaymentRead],
    summary="Historique des paiements d'une vente",
    responses=error_responses(404),
)
def list_sale_payments(
    sale_id: int, db: DbSession, current_user: Annotated[User, require_permission(P.PAYMENT_VIEW)]
):
    """Tous les paiements de la vente, du plus ancien au plus récent (rien n'est jamais écrasé)."""
    return sale_service.get_sale(db, current_user, sale_id).payments


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
    """Remet les quantités dans le stock du magasin (mouvements RETURN).
    Erreur SALE_ALREADY_CANCELLED si la vente est déjà annulée."""
    return sale_service.cancel_sale(db, current_user, sale_id, data, ip_address)
