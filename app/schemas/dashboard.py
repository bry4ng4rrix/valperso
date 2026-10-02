from datetime import date
from typing import Literal

from pydantic import BaseModel, Field

from app.schemas.common import DateRangeQuery, DisplayStr, Money, Pagination, SignedMoney
from app.schemas.sale import SaleSummary
from app.schemas.store import StoreSummary


class DashboardQuery(DateRangeQuery):
    store_id: int | None = Field(None, description="Limiter les statistiques à un magasin")


class SalesStatsQuery(DashboardQuery):
    group_by: Literal["day", "month"] = "day"


class TopProductsQuery(DashboardQuery):
    limit: int = Field(10, ge=1, le=50)


class LowStockQuery(Pagination):
    store_id: int | None = None


class StockValueQuery(BaseModel):
    store_id: int | None = None
    product_id: int | None = Field(None, description="Valeur du stock d'un seul produit")


class TopProduct(BaseModel):
    product_id: int
    reference: DisplayStr
    name: DisplayStr
    quantity_sold: int
    revenue: Money = Field(description="Montant des lignes vendues, avant remise globale de la vente")


class SalesStatPoint(BaseModel):
    period: date
    sales_count: int
    revenue: Money


class StockValue(BaseModel):
    quantity: int
    purchase_value: Money = Field(description="Quantité x prix d'achat")
    sale_value: Money = Field(description="Quantité x prix de vente (potentiel de vente)")
    potential_profit: SignedMoney = Field(description="Valeur de vente - valeur d'achat")


class StoreStockValue(StockValue):
    store: StoreSummary


class StockValueReport(BaseModel):
    stores: list[StoreStockValue]
    total: StockValue = Field(description="Stock global = somme des magasins (inchangé par les transferts)")


class DashboardSummary(BaseModel):
    sales_count: int
    revenue: Money = Field(description="Chiffre d'affaires : total des ventes non annulées")
    estimated_profit: SignedMoney = Field(description="Chiffre d'affaires - coût d'achat des articles vendus")
    amount_collected: Money = Field(description="Encaissements : paiements reçus sur la période")
    debt_amount: Money = Field(description="Total des restes à payer des ventes de la période")
    products_count: int = Field(description="Produits actifs au catalogue")
    stores_count: int = Field(description="Magasins actifs")
    stock_quantity: int = Field(description="Unités en stock (magasin filtré, sinon tous les magasins)")
    low_stock_count: int = Field(description="Lignes de stock sous le seuil d'alerte")
    out_of_stock_count: int = Field(description="Lignes de stock à zéro dans un magasin")
    unavailable_products_count: int = Field(
        description="Produits actifs à zéro dans TOUS les magasins (réellement indisponibles)"
    )
    top_products: list[TopProduct]
    recent_sales: list[SaleSummary]
