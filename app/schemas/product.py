from datetime import datetime

from pydantic import Field

from app.schemas.category import CategorySummary
from app.schemas.common import DisplayStr, InputModel, Money, ORMModel, PageQuery, UpdateModel, UpperStr

REFERENCE_PATTERN = r"^[A-Za-z0-9._/-]+$"


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
    purchase_price: Money
    selling_price: Money
    is_active: bool
    created_at: datetime
    updated_at: datetime


class ProductCreate(InputModel):
    """Une ligne de stock à 0 est créée automatiquement dans le Stock Local."""

    reference: UpperStr = Field(min_length=1, max_length=50, pattern=REFERENCE_PATTERN, examples=["P-001"])
    name: UpperStr = Field(min_length=2, max_length=200)
    category_id: int | None = Field(None, gt=0)
    purchase_price: Money
    selling_price: Money


class ProductUpdate(UpdateModel):
    NON_NULLABLE = ("reference", "name", "purchase_price", "selling_price", "is_active")

    reference: UpperStr | None = Field(None, min_length=1, max_length=50, pattern=REFERENCE_PATTERN)
    name: UpperStr | None = Field(None, min_length=2, max_length=200)
    category_id: int | None = Field(None, gt=0)
    purchase_price: Money | None = None
    selling_price: Money | None = None
    is_active: bool | None = None


class ProductFilters(PageQuery):
    search: str | None = Field(None, max_length=100, description="Recherche sur la référence ou le nom")
    category_id: int | None = None
    is_active: bool | None = None
