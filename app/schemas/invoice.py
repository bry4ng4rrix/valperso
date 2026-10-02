import datetime as dt

from pydantic import Field

from app.models.enums import DiscountType, PaymentStatus, SaleStatus
from app.schemas.common import DisplayStr, Money, ORMModel
from app.schemas.customer import CustomerSummary
from app.schemas.payment import PaymentRead
from app.schemas.sale import SaleItemRead
from app.schemas.user import UserSummary


class InvoiceStore(ORMModel):
    id: int
    name: DisplayStr
    address: DisplayStr | None
    phone: str | None


class InvoiceRead(ORMModel):
    """Facture d'une vente : tout ce qu'il faut pour l'imprimer ou l'envoyer au client."""

    invoice_number: str = Field(validation_alias="sale_number", description="Ex. FAC-2026-000125")
    date: dt.datetime = Field(validation_alias="created_at")
    store: InvoiceStore
    user: UserSummary
    customer: CustomerSummary
    lines: list[SaleItemRead] = Field(validation_alias="items")
    subtotal: Money
    discount_type: DiscountType
    discount_value: Money
    discount_amount: Money
    total: Money
    payments: list[PaymentRead]
    amount_paid: Money
    remaining_amount: Money
    payment_status: PaymentStatus
    payment_due_date: dt.date | None
    status: SaleStatus
