from datetime import datetime

from pydantic import BaseModel, Field, model_validator

from app.models.enums import TransferStatus
from app.schemas.common import DateRangeQuery, InputModel, ORMModel, PageQuery
from app.schemas.product import ProductSummary
from app.schemas.stock import MAX_QUANTITY
from app.schemas.store import StoreSummary
from app.schemas.user import UserSummary


class TransferItemCreate(InputModel):
    product_id: int = Field(gt=0)
    quantity: int = Field(gt=0, le=MAX_QUANTITY)


class StockTransferCreate(InputModel):
    source_store_id: int | None = Field(
        None, gt=0, description="Par défaut : le Stock Local (ADMIN) ou le magasin du vendeur"
    )
    destination_store_id: int = Field(gt=0)
    items: list[TransferItemCreate] = Field(min_length=1, max_length=200)

    @model_validator(mode="after")
    def _check_transfer(self):
        product_ids = [item.product_id for item in self.items]
        if len(product_ids) != len(set(product_ids)):
            raise ValueError("Chaque produit ne doit apparaître qu'une seule fois dans le transfert")
        if self.source_store_id == self.destination_store_id:
            raise ValueError("Le magasin de destination doit être différent du magasin source")
        return self


class TransferItemRead(ORMModel):
    id: int
    product: ProductSummary
    quantity: int


class StockTransferRead(ORMModel):
    id: int
    reference: str = Field(description="Ex. TRF-2026-000001")
    source_store: StoreSummary
    destination_store: StoreSummary
    status: TransferStatus
    items: list[TransferItemRead]
    creator: UserSummary
    created_at: datetime
    completed_at: datetime | None


class TransferStockLevel(BaseModel):
    """Stock d'un produit dans les deux magasins après l'opération."""

    product: ProductSummary
    source_quantity: int
    destination_quantity: int


class StockTransferResult(StockTransferRead):
    stock_levels: list[TransferStockLevel]


class StockTransferFilters(PageQuery, DateRangeQuery):
    store_id: int | None = Field(
        None, description="Transferts dont ce magasin est la source ou la destination"
    )
    source_store_id: int | None = None
    destination_store_id: int | None = None
    product_id: int | None = None
    status: TransferStatus | None = None
