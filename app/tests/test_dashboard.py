from datetime import UTC, datetime, timedelta

import pytest

from app.core.permissions import PermissionCode, RoleName
from app.tests.helpers import due_date, sale_payload


@pytest.fixture
def activity(client, factory, admin_headers):
    """Stock Local : riz (100) et huile (3) ; une vente payée, une vente avec avance, une vente annulée,
    et un transfert vers un magasin (qui ne doit compter ni comme vente ni comme perte)."""
    shop = factory.store("Magasin 1")
    riz = factory.product(name="Riz", selling_price="3000", purchase_price="2000", stock=100)
    huile = factory.product(name="Huile", selling_price="10000", purchase_price="7000", stock=3)
    factory.product(name="Sel")  # 0 partout : réellement indisponible
    client.post("/api/v1/sales", headers=admin_headers, json=sale_payload((riz, 10), (huile, 1)))  # 40 000
    client.post(
        "/api/v1/sales",
        headers=admin_headers,
        json=sale_payload((riz, 5), payment={"method": "CARD", "amount": 5000}, payment_due_date=due_date()),
    )  # 15 000 dont 10 000 dus
    cancelled = client.post("/api/v1/sales", headers=admin_headers, json=sale_payload((huile, 1))).json()
    client.post(f"/api/v1/sales/{cancelled['id']}/cancel", headers=admin_headers, json={"reason": "Test"})
    client.post(
        "/api/v1/stock-transfers",
        headers=admin_headers,
        json={"destination_store_id": shop.id, "items": [{"product_id": riz.id, "quantity": 85}]},
    )
    return {"shop": shop, "riz": riz, "huile": huile}


def test_summary(client, admin_headers, activity):
    body = client.get("/api/v1/dashboard/summary", headers=admin_headers).json()

    assert body["sales_count"] == 2
    assert body["revenue"] == 55000.0  # le transfert n'est pas un chiffre d'affaires
    assert body["estimated_profit"] == 18000.0  # 55 000 - (15 x 2000 + 1 x 7000)
    assert body["amount_collected"] == 45000.0
    assert body["debt_amount"] == 10000.0
    assert (body["products_count"], body["stores_count"]) == (3, 2)
    assert body["stock_quantity"] == 87  # 100 - 15 vendus + 2 huiles ; le transfert ne change pas le total
    assert body["low_stock_count"] == 1  # huile : 2 <= seuil
    # Sel à zéro dans le Stock Local ; le riz restant (85) a été déplacé en totalité vers le magasin :
    # il a quitté le Stock Local et ne compte donc pas comme rupture.
    assert body["out_of_stock_count"] == 1
    assert body["unavailable_products_count"] == 1  # seul le sel n'existe nulle part
    assert [(p["name"], p["quantity_sold"]) for p in body["top_products"]] == [("riz", 15), ("huile", 1)]
    assert len(body["recent_sales"]) == 3


def test_summary_by_store(client, admin_headers, activity):
    body = client.get(
        "/api/v1/dashboard/summary", headers=admin_headers, params={"store_id": activity["shop"].id}
    ).json()
    assert body["sales_count"] == 0 and body["revenue"] == 0.0
    assert body["stock_quantity"] == 85 and body["out_of_stock_count"] == 0


def test_summary_period_filter(client, admin_headers, activity):
    future = (datetime.now(UTC) + timedelta(days=1)).isoformat()
    body = client.get("/api/v1/dashboard/summary", headers=admin_headers, params={"date_from": future}).json()
    assert body["sales_count"] == 0 and body["revenue"] == 0.0


def test_stock_value_per_store_and_global(client, factory, admin_headers):
    """10 unités à 5 000 (achat) / 8 000 (vente) : 50 000 / 80 000 / bénéfice potentiel 30 000."""
    shop = factory.store()
    product = factory.product(purchase_price="5000", selling_price="8000", stock=10)
    client.post(
        "/api/v1/stock-transfers",
        headers=admin_headers,
        json={"destination_store_id": shop.id, "items": [{"product_id": product.id, "quantity": 4}]},
    )

    report = client.get("/api/v1/dashboard/stock-value", headers=admin_headers).json()

    by_store = {line["store"]["id"]: line for line in report["stores"]}
    assert (by_store[shop.id]["quantity"], by_store[shop.id]["purchase_value"]) == (4, 20000.0)
    assert report["total"] == {
        "quantity": 10,
        "purchase_value": 50000.0,
        "sale_value": 80000.0,
        "potential_profit": 30000.0,
    }


def test_sales_by_day_and_top_products(client, admin_headers, activity):
    days = client.get("/api/v1/dashboard/sales", headers=admin_headers, params={"group_by": "day"}).json()
    months = client.get("/api/v1/dashboard/sales", headers=admin_headers, params={"group_by": "month"}).json()
    top = client.get("/api/v1/dashboard/top-products", headers=admin_headers, params={"limit": 1}).json()

    assert (days[0]["sales_count"], days[0]["revenue"]) == (2, 55000.0)
    assert months[0]["period"].endswith("-01")
    assert [p["name"] for p in top] == ["riz"]


def test_low_stock_alerts(client, admin_headers, activity):
    items = client.get("/api/v1/dashboard/low-stock", headers=admin_headers).json()["items"]
    assert {(line["product"]["name"], line["quantity"]) for line in items} == {
        ("sel", 0),
        ("huile", 2),
    }


def test_vendeur_dashboard_is_limited_to_his_store(client, factory, activity):
    factory.grant(RoleName.VENDEUR, PermissionCode.DASHBOARD_VIEW)
    headers = factory.headers(factory.vendeur(activity["shop"]))

    body = client.get("/api/v1/dashboard/summary", headers=headers).json()

    assert body["sales_count"] == 0 and body["stock_quantity"] == 85
    other = client.get("/api/v1/dashboard/summary", headers=headers, params={"store_id": 999})
    assert other.status_code == 403


def test_reports_require_report_permission(client, factory):
    headers = factory.headers(factory.vendeur(factory.store()))
    for url in ("/api/v1/dashboard/top-products", "/api/v1/dashboard/sales", "/api/v1/dashboard/stock-value"):
        assert client.get(url, headers=headers).status_code == 403
