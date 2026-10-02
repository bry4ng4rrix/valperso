from datetime import UTC, datetime, timedelta

import pytest

from app.core.config import settings
from app.core.permissions import RoleName
from tests.helpers import sale_payload


@pytest.fixture
def sales_data(client, factory):
    """Deux ventes validées et une vente annulée au STOCK LOCAL."""
    riz = factory.product(name="Riz", selling_price="3000", purchase_price="2000", stock=100)
    huile = factory.product(name="Huile", selling_price="10000", purchase_price="7000", stock=3)
    headers = factory.headers(factory.admin())
    client.post("/api/v1/sales", headers=headers, json=sale_payload((riz, 10), (huile, 1)))  # 40 000
    client.post("/api/v1/sales", headers=headers, json=sale_payload((riz, 5)))  # 15 000
    cancelled = client.post("/api/v1/sales", headers=headers, json=sale_payload((huile, 1))).json()
    client.post(f"/api/v1/sales/{cancelled['id']}/cancel", headers=headers, json={"reason": "Test"})
    return {"riz": riz, "huile": huile, "headers": headers}


def test_summary(client, sales_data):
    response = client.get("/api/v1/dashboard/summary", headers=sales_data["headers"])

    assert response.status_code == 200
    body = response.json()
    assert body["sales_count"] == 2
    assert body["revenue"] == 55000.0
    # Coût : 15 riz x 2000 + 1 huile x 7000 = 37 000
    assert body["estimated_profit"] == 18000.0
    assert body["products_count"] == 2
    assert body["low_stock_count"] == 1  # huile : 2 unités <= seuil
    assert [(p["name"], p["quantity_sold"], p["revenue"]) for p in body["top_products"]] == [
        ("riz", 15, 45000.0),
        ("huile", 1, 10000.0),
    ]
    assert len(body["recent_sales"]) == 3
    assert body["recent_sales"][0]["status"] == "CANCELLED"


def test_summary_period_filter(client, sales_data):
    future = (datetime.now(UTC) + timedelta(days=1)).isoformat()
    response = client.get(
        "/api/v1/dashboard/summary", headers=sales_data["headers"], params={"date_from": future}
    )
    assert response.json()["sales_count"] == 0
    assert response.json()["revenue"] == 0.0


def test_invalid_period_is_rejected(client, factory):
    now = datetime.now(UTC)
    response = client.get(
        "/api/v1/dashboard/summary",
        headers=factory.headers(factory.admin()),
        params={"date_from": now.isoformat(), "date_to": (now - timedelta(days=1)).isoformat()},
    )
    assert response.status_code == 422


def test_sales_by_day(client, sales_data):
    response = client.get(
        "/api/v1/dashboard/sales", headers=sales_data["headers"], params={"group_by": "day"}
    )
    points = response.json()
    assert len(points) == 1
    assert points[0]["sales_count"] == 2 and points[0]["revenue"] == 55000.0


def test_sales_by_month(client, sales_data):
    response = client.get(
        "/api/v1/dashboard/sales", headers=sales_data["headers"], params={"group_by": "month"}
    )
    assert response.json()[0]["period"].endswith("-01")


def test_low_stock_list(client, factory, sales_data):
    response = client.get("/api/v1/dashboard/low-stock", headers=sales_data["headers"])
    items = response.json()["items"]
    assert [(i["product"]["name"], i["quantity"], i["status"]) for i in items] == [
        ("huile", 2, "STOCK_FAIBLE")
    ]
    response = client.get(
        "/api/v1/dashboard/low-stock", headers=sales_data["headers"], params={"threshold": 1000}
    )
    assert response.json()["total"] == 2


def test_store_user_dashboard_is_limited_to_his_store(client, factory, sales_data):
    shop = factory.store()
    manager = factory.user(RoleName.MANAGER, shop)
    response = client.get("/api/v1/dashboard/summary", headers=factory.headers(manager))
    assert response.json()["sales_count"] == 0


def test_reports_require_report_permission(client, factory):
    vendeur_headers = factory.headers(factory.user(RoleName.VENDEUR))
    assert client.get("/api/v1/dashboard/summary", headers=vendeur_headers).status_code == 200
    assert client.get("/api/v1/dashboard/top-products", headers=vendeur_headers).status_code == 403
    assert client.get("/api/v1/dashboard/sales", headers=vendeur_headers).status_code == 403


def test_low_stock_threshold_default_comes_from_settings():
    assert settings.LOW_STOCK_THRESHOLD >= 2
