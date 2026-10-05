from fastapi import APIRouter

from app.api.v1 import (
    audit,
    auth,
    categories,
    chat,
    company,
    customers,
    dashboard,
    invoices,
    payments,
    permissions,
    products,
    realtime,
    roles,
    sales,
    stock,
    stock_transfers,
    stores,
    users,
)

api_router = APIRouter()

for module in (
    auth,
    users,
    roles,
    permissions,
    stores,
    categories,
    products,
    stock,
    stock_transfers,
    customers,
    sales,
    invoices,
    payments,
    dashboard,
    company,
    chat,
    audit,
    realtime,
):
    api_router.include_router(module.router)
