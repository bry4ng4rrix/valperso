from typing import Annotated

from fastapi import APIRouter, Query, status

from app.api.responses import PROTECTED, error_responses
from app.core.dependencies import ClientIP, DbSession, require_permission
from app.core.permissions import PermissionCode as P
from app.models import User
from app.schemas.common import Page, Pagination
from app.schemas.customer import CustomerContact, CustomerCreate, CustomerDebts, CustomerFilters, CustomerRead
from app.schemas.sale import SaleSummary
from app.services import customer_service

router = APIRouter(prefix="/customers", tags=["Clients"], responses=PROTECTED)


@router.get("", response_model=Page[CustomerRead], summary="Lister les clients")
def list_customers(
    db: DbSession,
    filters: Annotated[CustomerFilters, Query()],
    current_user: Annotated[User, require_permission(P.SALE_VIEW)],
):
    """Recherche : `search` (nom, prénom, téléphone), `phone`. Filtres : `has_debt`, `store_id`.
    Tri : `name`, `created_at`, `remaining_amount`, `total_amount`, `last_sale_date`."""
    return customer_service.list_customers(db, current_user, filters)


@router.get("/contacts", response_model=Page[CustomerContact], summary="Contacts clients et dettes")
def list_contacts(
    db: DbSession,
    filters: Annotated[CustomerFilters, Query()],
    current_user: Annotated[User, require_permission(P.SALE_VIEW)],
):
    """Pour chaque client : nombre d'achats, montant total, montant payé, reste à payer et date du
    dernier achat. Pour un VENDEUR, ces totaux ne portent que sur son magasin.
    Exemple : `?has_debt=true&sort=-remaining_amount` pour les plus grosses dettes."""
    return customer_service.list_contacts(db, current_user, filters)


@router.post(
    "",
    response_model=CustomerRead,
    status_code=status.HTTP_201_CREATED,
    summary="Créer un client",
)
def create_customer(
    data: CustomerCreate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.SALE_CREATE)],
):
    """Le téléphone est facultatif, mais il est exigé pour une vente avec avance ou à crédit."""
    return customer_service.create_customer(db, current_user, data, ip_address)


@router.get(
    "/{customer_id}",
    response_model=CustomerRead,
    summary="Détail d'un client",
    responses=error_responses(404),
)
def get_customer(customer_id: int, db: DbSession, _: Annotated[User, require_permission(P.SALE_VIEW)]):
    """Retourne la fiche du client."""
    return customer_service.get_customer(db, customer_id)


@router.get(
    "/{customer_id}/sales",
    response_model=Page[SaleSummary],
    summary="Historique d'achats d'un client",
    responses=error_responses(404),
)
def list_customer_sales(
    customer_id: int,
    db: DbSession,
    pagination: Annotated[Pagination, Query()],
    current_user: Annotated[User, require_permission(P.SALE_VIEW)],
):
    """Ventes du client, les plus récentes d'abord (limitées au magasin d'un VENDEUR)."""
    return customer_service.list_customer_sales(db, current_user, customer_id, pagination)


@router.get(
    "/{customer_id}/debts",
    response_model=CustomerDebts,
    summary="Dettes d'un client",
    responses=error_responses(404),
)
def get_customer_debts(
    customer_id: int, db: DbSession, current_user: Annotated[User, require_permission(P.SALE_VIEW)]
):
    """Ventes non soldées (facture, total, payé, reste, échéance, historique des paiements)
    et dette totale du client (somme des restes à payer)."""
    return customer_service.get_customer_debts(db, current_user, customer_id)
