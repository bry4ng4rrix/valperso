import pytest

from app.tests.helpers import due_date, sale_payload


def test_create_customer(client, admin_headers):
    response = client.post(
        "/api/v1/customers", headers=admin_headers, json={"first_name": "Jean", "last_name": "Rakoto", "phone": "0341234567"}
    )
    assert response.status_code == 201
    assert response.json()["first_name"] == "jean" and response.json()["phone"] == "0341234567"


def test_vendeur_can_create_and_view_customers(client, factory):
    headers = factory.headers(factory.vendeur(factory.store()))
    created = client.post("/api/v1/customers", headers=headers, json={"first_name": "Rasoa", "last_name": "Vola"})
    assert created.status_code == 201
    assert client.get(f"/api/v1/customers/{created.json()['id']}", headers=headers).status_code == 200


def test_search_by_name_and_phone(client, factory, admin_headers):
    factory.customer("Jean", "Rakoto", "0341234567")
    factory.customer("Rasoa", "Vola", "0329998877")

    def names(**params):
        items = client.get("/api/v1/customers", headers=admin_headers, params=params).json()["items"]
        return sorted(item["first_name"] for item in items)

    assert names(search="rakoto") == ["jean"]
    assert names(search="0329") == ["rasoa"]
    assert names(phone="1234567") == ["jean"]


@pytest.fixture
def jean_purchases(client, factory, admin_headers):
    """Jean : 3 achats (50 000 au total), 30 000 payés -> dette de 20 000."""
    shop = factory.store()
    customer = factory.customer("Jean", "Rakoto", "0341234567")
    product = factory.product(selling_price="10000", stock=20, store=shop)
    common = {"customer": customer, "store_id": shop.id}
    client.post("/api/v1/sales", headers=admin_headers, json=sale_payload((product, 1), **common))
    client.post(
        "/api/v1/sales",
        headers=admin_headers,
        json=sale_payload((product, 2), payment={"method": "CARD", "amount": 5000}, payment_due_date=due_date(10), **common),
    )
    client.post(
        "/api/v1/sales",
        headers=admin_headers,
        json=sale_payload((product, 2), payment={"method": "CARD", "amount": 15000}, payment_due_date=due_date(5), **common),
    )
    return {"customer": customer, "shop": shop}


def test_contacts_aggregate_purchases_and_debt(client, admin_headers, jean_purchases):
    contacts = client.get("/api/v1/customers/contacts", headers=admin_headers, params={"search": "0341234567"}).json()

    contact = contacts["items"][0]
    assert (contact["first_name"], contact["last_name"], contact["phone"]) == ("jean", "rakoto", "0341234567")
    assert contact["total_purchases"] == 3
    assert (contact["total_amount"], contact["total_paid"], contact["remaining_amount"]) == (50000.0, 30000.0, 20000.0)
    assert contact["has_debt"] is True and contact["last_sale_date"]


def test_has_debt_filter(client, factory, admin_headers, jean_purchases):
    factory.customer("Sans", "Dette", None)
    with_debt = client.get("/api/v1/customers", headers=admin_headers, params={"has_debt": True}).json()["items"]
    without_debt = client.get("/api/v1/customers", headers=admin_headers, params={"has_debt": False}).json()["items"]
    assert [c["id"] for c in with_debt] == [jean_purchases["customer"].id]
    assert jean_purchases["customer"].id not in {c["id"] for c in without_debt}


def test_customer_debts(client, admin_headers, jean_purchases):
    response = client.get(f"/api/v1/customers/{jean_purchases['customer'].id}/debts", headers=admin_headers)

    body = response.json()
    assert body["customer"]["phone"] == "0341234567"
    assert body["total_debt"] == 20000.0
    # Échéance la plus proche d'abord.
    assert [(s["remaining_amount"], s["payment_due_date"]) for s in body["sales"]] == [
        (5000.0, due_date(5)),
        (15000.0, due_date(10)),
    ]
    assert body["sales"][0]["payments"][0]["amount"] == 15000.0


def test_customer_sales_history(client, admin_headers, jean_purchases):
    response = client.get(f"/api/v1/customers/{jean_purchases['customer'].id}/sales", headers=admin_headers)
    assert response.json()["total"] == 3


def test_store_filter(client, factory, admin_headers, jean_purchases):
    other_store = factory.store()
    by_shop = client.get("/api/v1/customers", headers=admin_headers, params={"store_id": jean_purchases["shop"].id})
    by_other = client.get("/api/v1/customers", headers=admin_headers, params={"store_id": other_store.id})
    assert by_shop.json()["total"] == 1 and by_other.json()["total"] == 0


def test_vendeur_sees_debts_of_his_store_only(client, factory, jean_purchases):
    other_headers = factory.headers(factory.vendeur(factory.store()))
    customer_id = jean_purchases["customer"].id

    debts = client.get(f"/api/v1/customers/{customer_id}/debts", headers=other_headers).json()

    assert debts["total_debt"] == 0.0 and debts["sales"] == []


def test_unknown_customer(client, admin_headers):
    response = client.get("/api/v1/customers/999999", headers=admin_headers)
    assert response.status_code == 404 and response.json()["code"] == "CUSTOMER_NOT_FOUND"
