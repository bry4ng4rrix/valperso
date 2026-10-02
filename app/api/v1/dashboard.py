from typing import Annotated

from fastapi import APIRouter, Query

from app.api.responses import PROTECTED
from app.core.dependencies import DbSession, require_permission
from app.core.permissions import PermissionCode as P
from app.models import User
from app.schemas.common import Page
from app.schemas.dashboard import (
    DashboardQuery,
    DashboardSummary,
    LowStockQuery,
    SalesStatPoint,
    SalesStatsQuery,
    StockValueQuery,
    StockValueReport,
    TopProduct,
    TopProductsQuery,
)
from app.schemas.stock import StockRead
from app.services import dashboard_service

router = APIRouter(prefix="/dashboard", tags=["Tableau de bord"], responses=PROTECTED)


@router.get("/summary", response_model=DashboardSummary, summary="Indicateurs clés")
def get_summary(
    db: DbSession,
    query: Annotated[DashboardQuery, Query()],
    current_user: Annotated[User, require_permission(P.DASHBOARD_VIEW)],
):
    """Ventes, chiffre d'affaires, bénéfice estimé, encaissements, dettes, produits, magasins,
    stock (faible, à zéro dans un magasin, indisponible partout), meilleurs produits et ventes
    récentes. Sans dates, la période couvre tout l'historique."""
    return dashboard_service.get_summary(db, current_user, query)


@router.get("/sales", response_model=list[SalesStatPoint], summary="Ventes par jour ou par mois")
def get_sales_stats(
    db: DbSession,
    query: Annotated[SalesStatsQuery, Query()],
    current_user: Annotated[User, require_permission(P.REPORT_VIEW)],
):
    """Regroupement dans le fuseau horaire configuré (TIMEZONE)."""
    return dashboard_service.get_sales_stats(db, current_user, query)


@router.get("/top-products", response_model=list[TopProduct], summary="Produits les plus vendus")
def get_top_products(
    db: DbSession,
    query: Annotated[TopProductsQuery, Query()],
    current_user: Annotated[User, require_permission(P.REPORT_VIEW)],
):
    return dashboard_service.get_top_products(db, current_user, query)


@router.get("/low-stock", response_model=Page[StockRead], summary="Stocks en alerte (faibles ou en rupture)")
def get_low_stock(
    db: DbSession,
    query: Annotated[LowStockQuery, Query()],
    current_user: Annotated[User, require_permission(P.DASHBOARD_VIEW)],
):
    """Lignes de stock sous le seuil d'alerte ou à zéro, les plus critiques d'abord."""
    return dashboard_service.get_low_stock(db, current_user, query)


@router.get("/stock-value", response_model=StockValueReport, summary="Valeur du stock")
def get_stock_value(
    db: DbSession,
    query: Annotated[StockValueQuery, Query()],
    current_user: Annotated[User, require_permission(P.REPORT_VIEW)],
):
    """Par magasin et au global : quantité, valeur d'achat, valeur de vente et bénéfice potentiel.
    Le stock global est la somme des magasins : un transfert ne le modifie pas."""
    return dashboard_service.get_stock_value(db, current_user, query)
