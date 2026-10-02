"""Règle métier : PRIX DE VENTE >= PRIX DE STOCK, et calculs de bénéfice."""

import pytest
from sqlalchemy.exc import IntegrityError

from app.models import Product


def product_payload(purchase_price, selling_price):
    return {
        "reference": "P-1",
        "name": "Produit",
        "purchase_price": purchase_price,
        "selling_price": selling_price,
    }


@pytest.mark.parametrize(("purchase", "selling"), [(5000, 7000), (5000, 5000)], ids=["superieur", "egal"])
def test_selling_price_greater_or_equal_is_accepted(client, admin_headers, purchase, selling):
    response = client.post("/api/v1/products", headers=admin_headers, json=product_payload(purchase, selling))
    assert response.status_code == 201
    assert response.json()["unit_profit"] == float(selling - purchase)


def test_creating_a_product_below_stock_price_is_refused(client, admin_headers):
    response = client.post("/api/v1/products", headers=admin_headers, json=product_payload(5000, 4000))

    assert response.status_code == 422
    assert (
        "Le prix de vente doit être supérieur ou égal au prix de stock."
        in response.json()["errors"][0]["message"]
    )


def test_updating_both_prices_below_is_refused(client, factory, admin_headers):
    product = factory.product(purchase_price="5000", selling_price="7000")
    response = client.patch(
        f"/api/v1/products/{product.id}",
        headers=admin_headers,
        json={"purchase_price": 5000, "selling_price": 4000},
    )
    assert response.status_code == 422


@pytest.mark.parametrize(
    "changes",
    [{"selling_price": 4000}, {"purchase_price": 8000}],
    ids=["prix-vente-baisse", "prix-stock-hausse"],
)
def test_updating_one_price_is_checked_against_the_stored_one(client, factory, admin_headers, db, changes):
    """Un seul prix envoyé : le schéma ne peut pas comparer, le service applique la règle."""
    product = factory.product(purchase_price="5000", selling_price="7000")

    response = client.patch(f"/api/v1/products/{product.id}", headers=admin_headers, json=changes)

    assert response.status_code == 400
    assert response.json() == {
        "detail": "Le prix de vente doit être supérieur ou égal au prix de stock.",
        "code": "INVALID_SELLING_PRICE",
    }
    db.refresh(product)
    assert (product.purchase_price, product.selling_price) == (5000, 7000)


def test_valid_update_of_a_single_price(client, factory, admin_headers):
    product = factory.product(purchase_price="5000", selling_price="7000")
    response = client.patch(
        f"/api/v1/products/{product.id}", headers=admin_headers, json={"selling_price": 5000}
    )
    assert response.status_code == 200 and response.json()["unit_profit"] == 0.0


def test_database_also_refuses_a_selling_price_below_stock_price(factory, db):
    db.add(Product(reference="X", name="Hors API", purchase_price=5000, selling_price=4000))
    with pytest.raises(IntegrityError):
        db.flush()
    db.rollback()


def test_stock_line_values(client, factory, admin_headers):
    """10 unités, prix de stock 10 000, prix de vente 15 000."""
    product = factory.product(purchase_price="10000", selling_price="15000", stock=10)
    line = factory.add_stock(product, 0)

    body = client.get(f"/api/v1/stock/{line.id}", headers=admin_headers).json()

    assert (body["purchase_value"], body["sale_value"], body["potential_profit"]) == (
        100000.0,
        150000.0,
        50000.0,
    )


def test_stock_value_of_a_product_a_store_and_all_stores(client, factory, admin_headers):
    shop = factory.store()
    product = factory.product(purchase_price="10000", selling_price="15000", stock=10)
    factory.product(purchase_price="1000", selling_price="2000", stock=5)
    url = "/api/v1/dashboard/stock-value"

    before = client.get(url, headers=admin_headers).json()["total"]
    client.post(
        "/api/v1/stock-transfers",
        headers=admin_headers,
        json={"destination_store_id": shop.id, "items": [{"product_id": product.id, "quantity": 4}]},
    )
    after = client.get(url, headers=admin_headers).json()["total"]
    one_product = client.get(url, headers=admin_headers, params={"product_id": product.id}).json()
    one_store = client.get(url, headers=admin_headers, params={"store_id": shop.id}).json()

    assert before == after == {
        "quantity": 15, "purchase_value": 105000.0, "sale_value": 160000.0, "potential_profit": 55000.0
    }  # fmt: skip
    assert one_product["total"] == {
        "quantity": 10, "purchase_value": 100000.0, "sale_value": 150000.0, "potential_profit": 50000.0
    }  # fmt: skip
    assert one_store["total"]["potential_profit"] == 20000.0  # 4 x (15 000 - 10 000)
