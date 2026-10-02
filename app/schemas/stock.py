from datetime import datetime
from typing import Literal

from pydantic import Field, computed_field

from app.models.enums import StockMovementType
from app.schemas.category import CategorySummary
from app.schemas.common import (
    DateRangeQuery,
    DisplayStr,
    InputModel,
    Money,
    OptionalUpperStr,
    ORMModel,
    PageQuery,
    Pagination,
    UpperStr,
)
from app.schemas.product import ProductSummary
from app.schemas.store import StoreSummary
from app.schemas.user import UserSummary

MAX_QUANTITY = 1_000_000

STORE_FIELD_DESCRIPTION = (
    "Magasin concerné. VENDEUR : toujours son propre magasin. "
    "ADMIN : par défaut son magasin d'affectation, sinon le Stock Local."
)


# --- Lignes de stock -----------------------------------------------------------------------------


class StockProduct(ORMModel):
    id: int
    reference: DisplayStr
    name: DisplayStr
    category: CategorySummary | None
    purchase_price: Money
    selling_price: Money
    is_active: bool


class StockRead(ORMModel):
    """Quantité d'un produit dans un magasin, avec ses états d'alerte calculés."""

    id: int
    product: StockProduct
    store: StoreSummary
    quantity: int
    alert_threshold: int
    low_stock: bool = Field(description="0 < quantité <= seuil d'alerte")
    out_of_stock: bool = Field(description="Quantité = 0 dans ce magasin")
    updated_at: datetime

    @computed_field(description="Valeur du stock = quantité x prix de stock")
    @property
    def purchase_value(self) -> Money:
        return self.quantity * self.product.purchase_price

    @computed_field(description="Valeur de vente potentielle = quantité x prix de vente")
    @property
    def sale_value(self) -> Money:
        return self.quantity * self.product.selling_price

    @computed_field(description="Bénéfice potentiel = valeur de vente - valeur du stock")
    @property
    def potential_profit(self) -> Money:
        return self.sale_value - self.purchase_value


class StockFilters(PageQuery):
    store_id: int | None = None
    product_id: int | None = None
    category_id: int | None = None
    low_stock: bool | None = None
    out_of_stock: bool | None = None
    search: str | None = Field(
        None, max_length=100, description="Nom, référence, catégorie, ou prix exact du produit"
    )


class StockAlertFilters(Pagination):
    store_id: int | None = None
    search: str | None = Field(None, max_length=100)


class AlertThresholdUpdate(InputModel):
    alert_threshold: int = Field(ge=0, le=MAX_QUANTITY)


# --- Mouvements ----------------------------------------------------------------------------------


class StockEntryCreate(InputModel):
    product_id: int = Field(gt=0)
    quantity: int = Field(gt=0, le=MAX_QUANTITY)
    store_id: int | None = Field(None, gt=0, description=STORE_FIELD_DESCRIPTION)
    reason: OptionalUpperStr = Field(None, max_length=255)
    reference: OptionalUpperStr = Field(None, max_length=100, description="Ex. n° de bon de livraison")


class StockExitCreate(StockEntryCreate):
    type: Literal[StockMovementType.EXIT, StockMovementType.LOSS] = Field(
        StockMovementType.EXIT, description="EXIT (sortie) ou LOSS (perte, casse, vol...)"
    )


class StockAdjustmentCreate(InputModel):
    product_id: int = Field(gt=0)
    store_id: int | None = Field(None, gt=0, description=STORE_FIELD_DESCRIPTION)
    new_quantity: int = Field(ge=0, le=MAX_QUANTITY, description="Quantité réellement comptée")
    reason: UpperStr = Field(min_length=3, max_length=255)


class StockMovementRead(ORMModel):
    id: int
    product: ProductSummary
    store: StoreSummary
    user: UserSummary
    type: StockMovementType
    quantity: int = Field(description="Positive pour une entrée, négative pour une sortie")
    reason: DisplayStr | None
    reference: str | None = Field(description="Document d'origine (n° de facture, de transfert...)")
    created_at: datetime


class StockMovementFilters(PageQuery, DateRangeQuery):
    product_id: int | None = None
    store_id: int | None = None
    user_id: int | None = None
    type: StockMovementType | None = None
    reference: str | None = Field(None, max_length=100)
