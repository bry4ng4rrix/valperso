from datetime import datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, Field, model_validator

from app.models.enums import CashRegisterStatus, CashTransactionType
from app.schemas.common import (
    DateRangeQuery,
    DisplayStr,
    InputModel,
    Money,
    OptionalUpperStr,
    ORMModel,
    PageQuery,
    SignedMoney,
    UpperStr,
)

# Types saisis manuellement. SALE et REFUND sont créés automatiquement par les ventes.
ManualCashTransactionType = Literal[
    CashTransactionType.EXPENSE,
    CashTransactionType.WITHDRAWAL,
    CashTransactionType.DEPOSIT,
    CashTransactionType.ADJUSTMENT,
]


class CashRegisterOpen(InputModel):
    store_id: int | None = Field(
        None, gt=0, description="Par défaut : le magasin de l'utilisateur, sinon le STOCK LOCAL"
    )
    opening_amount: Money = Field(Decimal("0"), description="Fond de caisse à l'ouverture")


class CashRegisterClose(InputModel):
    closing_amount: Money = Field(description="Montant réellement compté dans la caisse")


class CashRegisterRead(ORMModel):
    id: int
    store_id: int
    opened_by: int | None = Field(description="null si la caisse a été ouverte automatiquement")
    closed_by: int | None
    opening_amount: Money
    closing_amount: Money | None
    expected_amount: SignedMoney = Field(description="Montant théorique en caisse")
    difference: SignedMoney | None = Field(description="closing_amount - expected_amount (négatif = manque)")
    status: CashRegisterStatus
    opened_at: datetime
    closed_at: datetime | None
    opened_automatically: bool = Field(description="Ouverte par le serveur à l'heure d'ouverture")
    closed_automatically: bool = Field(
        description="Clôturée par le serveur à l'heure de fermeture (montant compté = montant théorique)"
    )


class CashTransactionCreate(InputModel):
    type: ManualCashTransactionType
    amount: SignedMoney = Field(
        description=(
            "Montant positif pour EXPENSE, WITHDRAWAL et DEPOSIT (le sens dépend du type). "
            "Pour ADJUSTMENT : positif pour ajouter, négatif pour retirer."
        )
    )
    reason: UpperStr = Field(min_length=3, max_length=255)
    reference: OptionalUpperStr = Field(None, max_length=100)

    @model_validator(mode="after")
    def _check_amount(self):
        if self.amount == 0:
            raise ValueError("Le montant ne peut pas être nul")
        if self.type != CashTransactionType.ADJUSTMENT and self.amount < 0:
            raise ValueError("Le montant doit être positif : le sens de l'opération dépend de son type")
        return self


class CashTransactionRead(ORMModel):
    id: int
    cash_register_id: int
    type: CashTransactionType
    amount: SignedMoney = Field(description="Positif = entrée d'argent, négatif = sortie")
    reason: DisplayStr | None
    reference: str | None
    created_by: int
    created_at: datetime


class CashRegisterFilters(PageQuery, DateRangeQuery):
    store_id: int | None = None
    status: CashRegisterStatus | None = None


class CashScheduleRead(BaseModel):
    """Horaires d'ouverture et de fermeture automatiques des caisses."""

    enabled: bool
    open_time: str = Field(examples=["06:00"])
    close_time: str = Field(examples=["19:00"])
    timezone: str = Field(examples=["Indian/Antananarivo"])
