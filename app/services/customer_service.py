"""Clients : fiche, recherche, historique d'achats et dettes.

Le répertoire des clients est commun à tous les magasins (un client peut acheter partout).
En revanche, les achats et les dettes visibles par un VENDEUR sont limités à son magasin.
"""

from sqlalchemy.orm import Session

from app.core.exceptions import CustomerNotFound
from app.models import Customer, Sale, User
from app.repositories import customer_repository, sale_repository
from app.repositories.base import PageResult
from app.schemas.common import Pagination
from app.schemas.customer import (
    CustomerContact,
    CustomerCreate,
    CustomerDebts,
    CustomerFilters,
    CustomerRead,
    CustomerSummary,
    DebtSale,
)
from app.services import audit_service, store_access


def get_customer(db: Session, customer_id: int) -> Customer:
    customer = db.get(Customer, customer_id)
    if customer is None:
        raise CustomerNotFound(f"Client {customer_id} introuvable")
    return customer


def _add_customer(db: Session, user: User, data: CustomerCreate, ip_address: str | None) -> Customer:
    customer = Customer(**data.model_dump())
    db.add(customer)
    db.flush()
    audit_service.record(
        db,
        user_id=user.id,
        action="customer.create",
        entity_type="customer",
        entity_id=customer.id,
        new_data=audit_service.snapshot(CustomerRead, customer),
        ip_address=ip_address,
    )
    return customer


def create_customer(db: Session, user: User, data: CustomerCreate, ip_address: str | None = None) -> Customer:
    customer = _add_customer(db, user, data, ip_address)
    db.commit()
    return customer


def find_or_add_for_sale(db: Session, user: User, data: CustomerCreate, ip_address: str | None) -> Customer:
    """Client saisi pendant une vente : réutilise le client identique (nom, prénom, téléphone) s'il existe,
    sinon le crée. Pas de COMMIT ici : il est validé avec la vente (ou annulé avec elle)."""
    existing = customer_repository.find_same_customer(db, data.first_name, data.last_name, data.phone)
    return existing or _add_customer(db, user, data, ip_address)


def list_customers(db: Session, user: User, filters: CustomerFilters) -> PageResult[Customer]:
    scope_store_id = store_access.visible_store_id(user, filters.store_id)
    return customer_repository.list_customers(db, filters, scope_store_id)


def list_contacts(db: Session, user: User, filters: CustomerFilters) -> PageResult[CustomerContact]:
    """Clients avec le total de leurs achats, de leurs paiements et de leur dette."""
    scope_store_id = store_access.visible_store_id(user, filters.store_id)
    page = customer_repository.list_contacts(db, filters, scope_store_id)
    contacts = [
        CustomerContact(
            **CustomerSummary.model_validate(row.Customer).model_dump(),
            total_purchases=row.total_purchases,
            total_amount=row.total_amount,
            total_paid=row.total_paid,
            remaining_amount=row.remaining_amount,
            has_debt=row.remaining_amount > 0,
            last_sale_date=row.last_sale_date,
        )
        for row in page.items
    ]
    return PageResult(items=contacts, total=page.total, page=page.page, page_size=page.page_size)


def list_customer_sales(
    db: Session, user: User, customer_id: int, pagination: Pagination
) -> PageResult[Sale]:
    get_customer(db, customer_id)
    store_id = store_access.visible_store_id(user, None)
    return sale_repository.list_customer_sales(db, customer_id, store_id, pagination)


def get_customer_debts(db: Session, user: User, customer_id: int) -> CustomerDebts:
    """Ventes non soldées du client et total de sa dette (somme des restes à payer)."""
    customer = get_customer(db, customer_id)
    store_id = store_access.visible_store_id(user, None)
    sales = sale_repository.list_customer_debts(db, customer_id, store_id)
    return CustomerDebts(
        customer=CustomerSummary.model_validate(customer),
        total_debt=sum((sale.remaining_amount for sale in sales), 0),
        sales=[DebtSale.model_validate(sale) for sale in sales],
    )
