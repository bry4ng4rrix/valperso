from datetime import datetime

from pydantic import Field, model_validator

from app.models.enums import PaymentMethod
from app.schemas.common import (
    DateRangeQuery,
    DisplayStr,
    InputModel,
    Money,
    OptionalUpperStr,
    ORMModel,
    PageQuery,
)
from app.schemas.user import UserSummary


class PaymentRead(ORMModel):
    id: int
    sale_id: int
    method: PaymentMethod
    amount: Money
    reference: DisplayStr | None
    creator: UserSummary = Field(description="Utilisateur qui a encaissé")
    created_at: datetime


class PaymentCreate(InputModel):
    """Paiement d'une vente qui a un reste à payer (solde d'une avance ou d'une vente à crédit)."""

    sale_id: int = Field(gt=0)
    method: PaymentMethod
    amount: Money
    reference: OptionalUpperStr = Field(None, max_length=100, description="Ex. n° de transaction")

    @model_validator(mode="after")
    def _check_payment(self):
        if self.method == PaymentMethod.CREDIT:
            raise ValueError("CREDIT n'est pas un encaissement : choisissez le mode de paiement réel")
        if self.amount <= 0:
            raise ValueError("Le montant du paiement doit être supérieur à 0")
        return self


class PaymentFilters(PageQuery, DateRangeQuery):
    sale_id: int | None = None
    method: PaymentMethod | None = None
    store_id: int | None = None
