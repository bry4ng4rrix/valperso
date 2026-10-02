from datetime import date, datetime
from decimal import Decimal

from pydantic import Field, model_validator

from app.models.enums import DiscountType, PaymentMethod, PaymentStatus, SaleStatus
from app.schemas.common import (
    DateRangeQuery,
    DisplayStr,
    InputModel,
    Money,
    OptionalUpperStr,
    ORMModel,
    PageQuery,
    UpperStr,
)
from app.schemas.customer import CustomerCreate, CustomerSummary
from app.schemas.installment import SaleInstallmentRead
from app.schemas.payment import PaymentRead
from app.schemas.store import StoreSummary
from app.schemas.user import UserSummary
from app.utils.dates import local_today

# --- Création ------------------------------------------------------------------------------------


class SaleItemCreate(InputModel):
    product_id: int = Field(gt=0)
    quantity: int = Field(gt=0, le=100_000)
    description: OptionalUpperStr = Field(
        None, max_length=255, description="Précision pour cet article (taille, couleur...)"
    )


class SalePaymentCreate(InputModel):
    """Paiement versé au moment de la vente.

    - `amount` absent : paiement complet (égal au total calculé par le serveur).
    - `amount` inférieur au total : avance ; le reste devient une dette.
    - `method` = CREDIT : vente à crédit, rien n'est encaissé.
    """

    method: PaymentMethod
    amount: Money | None = Field(None, description="Montant versé. Absent = paiement complet")
    reference: OptionalUpperStr = Field(None, max_length=100, description="Ex. n° de transaction")

    @model_validator(mode="after")
    def _check_credit(self):
        if self.method == PaymentMethod.CREDIT and self.amount:
            raise ValueError("Avec CREDIT rien n'est encaissé : utilisez un mode réel pour une avance")
        return self


class SaleInstallmentCreate(InputModel):
    due_date: date = Field(description="Date du remboursement")
    amount: Money = Field(gt=0, description="Montant à rembourser à cette date")


class SaleCreate(InputModel):
    """Les prix, le sous-total, la remise, le total et le reste à payer sont calculés par le serveur.
    L'utilisateur responsable est toujours l'utilisateur connecté."""

    store_id: int | None = Field(
        None, gt=0, description="ADMIN uniquement (défaut : Stock Local). Un VENDEUR vend dans son magasin."
    )
    customer_id: int | None = Field(None, gt=0, description="Client existant")
    customer: CustomerCreate | None = Field(None, description="Ou nouveau client (nom, prénom, téléphone)")
    items: list[SaleItemCreate] = Field(min_length=1, max_length=200)
    discount_type: DiscountType = DiscountType.NONE
    discount_value: Money = Field(Decimal("0"), description="Pourcentage (0-100) ou montant fixe")
    payment: SalePaymentCreate | None = Field(None, description="Absent = vente à crédit (rien encaissé)")
    payment_due_date: date | None = Field(
        None, description="Échéance unique du reste à payer (si `installments` est absent)"
    )
    installments: list[SaleInstallmentCreate] | None = Field(
        None,
        max_length=36,
        description="Échéancier du reste à payer : la somme des montants doit être égale au reste à payer",
    )

    @model_validator(mode="after")
    def _check_sale(self):
        if (self.customer_id is None) == (self.customer is None):
            raise ValueError("Indiquez soit customer_id (client existant), soit customer (nouveau client)")

        product_ids = [item.product_id for item in self.items]
        if len(product_ids) != len(set(product_ids)):
            raise ValueError("Chaque produit ne doit apparaître qu'une seule fois dans la vente")

        if self.discount_type == DiscountType.NONE and self.discount_value != 0:
            raise ValueError("discount_value doit valoir 0 lorsque discount_type vaut NONE")
        if self.discount_type != DiscountType.NONE and self.discount_value == 0:
            raise ValueError("discount_value doit être supérieure à 0 pour appliquer une remise")
        if self.discount_type == DiscountType.PERCENTAGE and self.discount_value > 100:
            raise ValueError("Une remise en pourcentage ne peut pas dépasser 100")

        today = local_today()
        if self.payment_due_date is not None and self.payment_due_date < today:
            raise ValueError("La date d'échéance ne peut pas être dans le passé")
        if self.installments:
            dates = [installment.due_date for installment in self.installments]
            if len(dates) != len(set(dates)):
                raise ValueError("Deux échéances ne peuvent pas avoir la même date")
            if min(dates) < today:
                raise ValueError("Une date de remboursement ne peut pas être dans le passé")
        return self


class SaleCancel(InputModel):
    reason: UpperStr = Field(min_length=3, max_length=255, description="Motif de l'annulation")


# --- Lecture -------------------------------------------------------------------------------------


class SaleItemRead(ORMModel):
    id: int
    product_id: int
    product_reference: DisplayStr
    product_name: DisplayStr
    description: DisplayStr | None
    quantity: int
    unit_price: Money
    total: Money


class SaleSummary(ORMModel):
    """Ligne de l'historique des ventes."""

    id: int
    sale_number: str = Field(description="Numéro de facture, ex. FAC-2026-000125")
    created_at: datetime
    customer: CustomerSummary
    user: UserSummary = Field(description="Utilisateur connecté qui a réalisé la vente")
    store: StoreSummary
    total: Money
    amount_paid: Money
    remaining_amount: Money
    payment_status: PaymentStatus
    payment_due_date: date | None = Field(description="Prochaine échéance non payée")
    status: SaleStatus


class SaleRead(SaleSummary):
    subtotal: Money
    discount_type: DiscountType
    discount_value: Money
    discount_amount: Money
    items: list[SaleItemRead]
    payments: list[PaymentRead]
    installments: list[SaleInstallmentRead] = Field(validation_alias="installment_schedule")
    updated_at: datetime


class SaleHistoryFilters(PageQuery, DateRangeQuery):
    search: str | None = Field(
        None, max_length=100, description="N° de facture, nom, prénom ou téléphone du client"
    )
    user_id: int | None = None
    store_id: int | None = None
    customer_id: int | None = None
    payment_status: PaymentStatus | None = None
    has_debt: bool | None = Field(None, description="Ventes avec (ou sans) reste à payer")
    status: SaleStatus | None = None
