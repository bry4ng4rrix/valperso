from datetime import date, datetime

from pydantic import BaseModel, Field

from app.models.enums import PaymentStatus
from app.schemas.common import DisplayStr, InputModel, Money, OptionalPhone, ORMModel, PageQuery
from app.schemas.payment import PaymentRead
from app.schemas.store import StoreSummary
from app.schemas.user import PersonName


class CustomerCreate(InputModel):
    first_name: PersonName
    last_name: PersonName
    phone: OptionalPhone = Field(None, description="Obligatoire pour une vente avec avance ou à crédit")


class CustomerSummary(ORMModel):
    id: int
    first_name: DisplayStr
    last_name: DisplayStr
    phone: str | None


class CustomerRead(CustomerSummary):
    created_at: datetime
    updated_at: datetime


class CustomerFilters(PageQuery):
    search: str | None = Field(None, max_length=100, description="Nom, prénom ou téléphone")
    phone: str | None = Field(None, max_length=30, description="Téléphone (recherche partielle)")
    has_debt: bool | None = Field(None, description="Clients ayant (ou non) un reste à payer")
    store_id: int | None = Field(None, description="Clients ayant acheté dans ce magasin")


class CustomerContact(BaseModel):
    """Client avec le résumé de ses achats et de sa dette (dans les magasins visibles)."""

    id: int
    first_name: DisplayStr
    last_name: DisplayStr
    phone: str | None
    total_purchases: int
    total_amount: Money
    total_paid: Money
    remaining_amount: Money
    has_debt: bool
    last_sale_date: datetime | None


class DebtSale(ORMModel):
    """Vente non soldée : facture, montants, échéance et historique des paiements."""

    id: int
    sale_number: str
    created_at: datetime
    store: StoreSummary
    total: Money
    amount_paid: Money
    remaining_amount: Money
    payment_status: PaymentStatus
    payment_due_date: date | None
    payments: list[PaymentRead]


class CustomerDebts(BaseModel):
    customer: CustomerSummary
    total_debt: Money = Field(description="Somme des restes à payer")
    sales: list[DebtSale]
