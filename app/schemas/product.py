from datetime import datetime
from decimal import Decimal

from pydantic import Field, computed_field, model_validator

from app.core.exceptions import InvalidSellingPrice
from app.schemas.category import CategorySummary
from app.schemas.common import DisplayStr, InputModel, Money, ORMModel, PageQuery, UpdateModel, UpperStr

REFERENCE_PATTERN = r"^[A-Za-z0-9._/-]+$"


def check_selling_price(purchase_price: Decimal | None, selling_price: Decimal | None) -> None:
    """Règle métier : prix de vente >= prix de stock (prix d'achat)."""
    if purchase_price is not None and selling_price is not None and selling_price < purchase_price:
        raise ValueError(InvalidSellingPrice.default_message)


class ProductSummary(ORMModel):
    id: int
    reference: DisplayStr
    name: DisplayStr


class ProductRead(ORMModel):
    id: int
    reference: DisplayStr = Field(description="Référence (non unique)")
    name: DisplayStr = Field(description="Nom (non unique)")
    category_id: int | None
    category: CategorySummary | None
    purchase_price: Money = Field(description="Prix de stock (prix d'achat)")
    selling_price: Money = Field(description="Prix de vente, toujours >= prix de stock")
    is_active: bool
    created_at: datetime
    updated_at: datetime

    @computed_field(description="Bénéfice unitaire = prix de vente - prix de stock")
    @property
    def unit_profit(self) -> Money:
        return self.selling_price - self.purchase_price


class ProductCreate(InputModel):
    """Une ligne de stock à 0 est créée automatiquement dans le Stock Local."""

    reference: UpperStr = Field(min_length=1, max_length=50, pattern=REFERENCE_PATTERN, examples=["P-001"])
    name: UpperStr = Field(min_length=2, max_length=200)
    category_id: int | None = Field(None, gt=0)
    purchase_price: Money = Field(description="Prix de stock (prix d'achat)")
    selling_price: Money = Field(description="Prix de vente : doit être >= prix de stock")

    @model_validator(mode="after")
    def _check_prices(self):
        check_selling_price(self.purchase_price, self.selling_price)
        return self


class ProductUpdate(UpdateModel):
    NON_NULLABLE = ("reference", "name", "purchase_price", "selling_price", "is_active")

    reference: UpperStr | None = Field(None, min_length=1, max_length=50, pattern=REFERENCE_PATTERN)
    name: UpperStr | None = Field(None, min_length=2, max_length=200)
    category_id: int | None = Field(None, gt=0)
    purchase_price: Money | None = None
    selling_price: Money | None = None
    is_active: bool | None = None

    @model_validator(mode="after")
    def _check_prices(self):
        # Si un seul des deux prix est envoyé, le service compare avec le prix déjà enregistré.
        check_selling_price(self.purchase_price, self.selling_price)
        return self


class ProductFilters(PageQuery):
    search: str | None = Field(
        None, max_length=100, description="Nom, référence, catégorie, ou prix exact (ex. 200000 ou 200 000)"
    )
    category_id: int | None = None
    is_active: bool | None = None
