from fastapi import APIRouter

from app.api.v1 import (
    audit,
    auth,
    cash,
    categories,
    chat,
    dashboard,
    payments,
    permissions,
    products,
    roles,
    sales,
    stock,
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
    sales,
    payments,
    cash,
    dashboard,
    chat,
    audit,
):
    api_router.include_router(module.router)
