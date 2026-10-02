import datetime as dt

from pydantic import Field, computed_field

from app.models.enums import DiscountType, PaymentStatus, SaleStatus
from app.schemas.common import DisplayStr, Money, ORMModel
from app.schemas.customer import CustomerSummary
from app.schemas.payment import PaymentRead
from app.schemas.sale import SaleItemRead
from app.schemas.user import UserSummary
from app.utils.text import display_text

THANK_YOU_MESSAGE = "Merci pour votre achat !"


class InvoiceCompany(ORMModel):
    """En-tête de la facture : informations de la société AU MOMENT DE LA VENTE (snapshot)."""

    name: DisplayStr = Field(validation_alias="company_name")
    logo_url: str | None
    address: DisplayStr | None
    city: DisplayStr | None
    phone: str | None
    email: str | None


class InvoiceStore(ORMModel):
    """Magasin de la vente, tel qu'il était au moment de la vente (snapshot)."""

    name: DisplayStr = Field(validation_alias="store_name")
    address: DisplayStr | None = Field(validation_alias="store_address")
    phone: str | None = Field(validation_alias="store_phone")


class InvoiceRead(ORMModel):
    """Facture d'une vente : tout ce qu'il faut pour l'imprimer ou l'envoyer au client.

    Elle ne dépend d'aucune donnée modifiable après la vente : la société, les produits (référence,
    nom, prix unitaire) et les montants sont ceux enregistrés au moment de la vente.
    """

    company: InvoiceCompany = Field(validation_alias="company_snapshot")
    invoice_number: str = Field(validation_alias="sale_number", description="Ex. FAC-2026-000125")
    date: dt.datetime = Field(validation_alias="created_at", description="Date et heure de la vente")
    store: InvoiceStore = Field(validation_alias="company_snapshot")
    user: UserSummary = Field(description="Vendeur / utilisateur qui a réalisé la vente")
    customer: CustomerSummary
    lines: list[SaleItemRead] = Field(validation_alias="items")
    subtotal: Money
    discount_type: DiscountType
    discount_value: Money
    discount_amount: Money
    total: Money = Field(description="Total après remise = sous-total - remise")
    payments: list[PaymentRead]
    amount_paid: Money
    remaining_amount: Money
    payment_status: PaymentStatus
    payment_due_date: dt.date | None = Field(description="Échéance du reste à payer (vente avec dette)")
    status: SaleStatus

    @computed_field(description="Message de remerciement, avec le nom de la société de la facture")
    @property
    def thank_you_message(self) -> list[str]:
        return [THANK_YOU_MESSAGE, f"À bientôt chez {display_text(self.company.name)}."]
