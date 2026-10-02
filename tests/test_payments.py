import pytest
from sqlalchemy import select

from app.core.permissions import RoleName
from app.models import CashRegister, CashTransaction
from tests.helpers import sale_payload


@pytest.fixture
def caissier(factory):
    return factory.user(RoleName.CAISSIER)


@pytest.fixture
def credit_sale(client, factory, caissier):
    product = factory.product(selling_price="10000", stock=10)
    response = client.post(
        "/api/v1/sales",
        headers=factory.headers(caissier),
        json=sale_payload((product, 3), method="CREDIT", customer_name="Rasoa"),
    )
    return response.json()


def pay(client, headers, sale_id, amount, method="CASH"):
    return client.post(
        "/api/v1/payments", headers=headers, json={"sale_id": sale_id, "method": method, "amount": amount}
    )


def test_credit_sale_is_entirely_due(credit_sale):
    assert credit_sale["total"] == 30000.0
    assert credit_sale["amount_paid"] == 0.0
    assert credit_sale["amount_due"] == 30000.0


def test_settle_credit_sale_in_several_payments(client, factory, caissier, credit_sale, db):
    register = factory.open_register(factory.default_store(), caissier, "5000")
    headers = factory.headers(caissier)

    first = pay(client, headers, credit_sale["id"], 10000)
    second = pay(client, headers, credit_sale["id"], 20000, method="MOBILE_MONEY")

    assert first.status_code == 201 and second.status_code == 201
    sale = client.get(f"/api/v1/sales/{credit_sale['id']}", headers=headers).json()
    assert sale["amount_paid"] == 30000.0 and sale["amount_due"] == 0.0
    assert [p["method"] for p in sale["payments"]] == ["CREDIT", "CASH", "MOBILE_MONEY"]
    db.refresh(register)
    assert register.expected_amount == 15000  # seuls les 10 000 en espèces entrent en caisse


def test_payment_cannot_exceed_amount_due(client, factory, caissier, credit_sale):
    response = pay(client, factory.headers(caissier), credit_sale["id"], 30001, method="CARD")
    assert response.status_code == 400
    assert response.json()["code"] == "PAYMENT_EXCEEDS_DUE"


def test_fully_paid_sale_refuses_new_payment(client, factory, caissier):
    product = factory.product(stock=5)
    headers = factory.headers(caissier)
    sale = client.post(
        "/api/v1/sales", headers=headers, json=sale_payload((product, 1), method="CARD")
    ).json()

    response = pay(client, headers, sale["id"], 100, method="CARD")

    assert response.status_code == 400
    assert response.json()["code"] == "SALE_ALREADY_PAID"


@pytest.mark.parametrize(("method", "amount"), [("CREDIT", 1000), ("CARD", 0), ("CARD", -10)])
def test_invalid_settlements_are_rejected(client, factory, caissier, credit_sale, method, amount):
    assert pay(client, factory.headers(caissier), credit_sale["id"], amount, method).status_code == 422


def test_payment_on_cancelled_sale_is_refused(client, factory, caissier, credit_sale):
    admin_headers = factory.headers(factory.admin())
    client.post(
        f"/api/v1/sales/{credit_sale['id']}/cancel", headers=admin_headers, json={"reason": "Annulée"}
    )
    assert pay(client, admin_headers, credit_sale["id"], 1000, method="CARD").status_code == 400


def test_non_cash_sale_does_not_touch_the_cash_register(client, factory, caissier, db):
    register = factory.open_register(factory.default_store(), caissier, "1000")
    product = factory.product(stock=5)

    client.post(
        "/api/v1/sales", headers=factory.headers(caissier), json=sale_payload((product, 1), method="CARD")
    )

    assert db.get(CashRegister, register.id).expected_amount == 1000
    assert db.scalars(select(CashTransaction)).all() == []


def test_vendeur_cannot_record_a_settlement(client, factory, credit_sale):
    vendeur = factory.user(RoleName.VENDEUR)
    assert pay(client, factory.headers(vendeur), credit_sale["id"], 1000, method="CARD").status_code == 403


def test_list_payments_of_a_sale(client, factory, caissier, credit_sale):
    response = client.get(
        "/api/v1/payments", headers=factory.headers(caissier), params={"sale_id": credit_sale["id"]}
    )
    assert response.status_code == 200
    assert [(p["method"], p["amount"]) for p in response.json()["items"]] == [("CREDIT", 30000.0)]
