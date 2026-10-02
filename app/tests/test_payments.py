"""Paiement complet, avance, dette, échéance, paiements multiples (exemples de la spécification)."""

import pytest
from sqlalchemy import select

from app.models import AuditLog, CashRegister
from app.tests.helpers import due_date, sale_payload


@pytest.fixture
def shop(factory):
    return factory.store()


@pytest.fixture
def seller(factory, shop):
    return factory.vendeur(shop)


@pytest.fixture
def headers(factory, seller):
    return factory.headers(seller)


@pytest.fixture
def register(factory, shop, seller):
    return factory.open_register(shop, seller)


@pytest.fixture
def article(factory, shop):
    return factory.product(selling_price="20000", stock=10, store=shop)  # total d'une vente : 20 000 Ar


def create_sale(client, headers, article, **fields):
    return client.post("/api/v1/sales", headers=headers, json=sale_payload((article, 1), **fields))


def pay(client, headers, sale_id, amount, method="CASH"):
    return client.post(
        "/api/v1/payments", headers=headers, json={"sale_id": sale_id, "method": method, "amount": amount}
    )


def test_full_payment(client, headers, article, register):
    body = create_sale(client, headers, article, payment={"method": "CASH", "amount": 20000}).json()
    assert (body["total"], body["amount_paid"], body["remaining_amount"]) == (20000.0, 20000.0, 0.0)
    assert body["payment_status"] == "PAID" and body["payment_due_date"] is None


def test_advance_then_balance(client, db, headers, article, register):
    """Avance de 10 000 sur 20 000 avec échéance, puis le client revient payer 10 000."""
    sale = create_sale(
        client, headers, article, payment={"method": "CASH", "amount": 10000}, payment_due_date=due_date()
    ).json()
    assert (sale["amount_paid"], sale["remaining_amount"], sale["payment_status"]) == (
        10000.0,
        10000.0,
        "PARTIAL",
    )
    assert sale["payment_due_date"] == due_date()

    response = pay(client, headers, sale["id"], 10000)

    assert response.status_code == 201
    final = client.get(f"/api/v1/sales/{sale['id']}", headers=headers).json()
    assert (final["total"], final["amount_paid"], final["remaining_amount"]) == (20000.0, 20000.0, 0.0)
    assert final["payment_status"] == "PAID"
    db.refresh(register)
    assert register.expected_amount == 20000  # deux encaissements de 10 000


def test_unpaid_sale_on_credit(client, headers, article):
    without_payment = create_sale(client, headers, article, payment=None, payment_due_date=due_date())
    explicit_credit = create_sale(
        client, headers, article, payment={"method": "CREDIT"}, payment_due_date=due_date()
    )

    for response in (without_payment, explicit_credit):
        body = response.json()
        assert response.status_code == 201
        assert (body["payment_status"], body["amount_paid"], body["remaining_amount"]) == (
            "UNPAID",
            0.0,
            20000.0,
        )
        assert body["payments"] == []


def test_debt_requires_due_date(client, headers, article):
    response = create_sale(client, headers, article, payment={"method": "CARD", "amount": 5000})
    assert response.status_code == 400 and response.json()["code"] == "INVALID_PAYMENT"
    assert "payment_due_date" in response.json()["detail"]


def test_debt_requires_customer_phone(client, headers, article):
    response = create_sale(
        client,
        headers,
        article,
        customer={"first_name": "Paul", "last_name": "Rabe"},
        payment={"method": "CARD", "amount": 5000},
        payment_due_date=due_date(),
    )
    assert response.status_code == 400 and "téléphone" in response.json()["detail"]


def test_due_date_in_the_past_is_refused(client, headers, article):
    response = create_sale(client, headers, article, payment=None, payment_due_date="2020-01-01")
    assert response.status_code == 422


def test_due_date_is_ignored_for_a_full_payment(client, headers, article):
    body = create_sale(
        client, headers, article, payment={"method": "CARD"}, payment_due_date=due_date()
    ).json()
    assert body["payment_due_date"] is None


def test_several_payments_are_all_kept(client, headers, article, register):
    """Vente de 20 000 réglée en trois fois : l'historique conserve les trois paiements."""
    sale = create_sale(client, headers, article, payment=None, payment_due_date=due_date()).json()
    statuses = []
    for amount, method in [(5000, "CASH"), (7000, "MOBILE_MONEY"), (8000, "CASH")]:
        pay(client, headers, sale["id"], amount, method)
        statuses.append(client.get(f"/api/v1/sales/{sale['id']}", headers=headers).json()["payment_status"])

    history = client.get(f"/api/v1/sales/{sale['id']}/payments", headers=headers).json()

    assert statuses == ["PARTIAL", "PARTIAL", "PAID"]
    assert [(p["amount"], p["method"]) for p in history] == [
        (5000.0, "CASH"),
        (7000.0, "MOBILE_MONEY"),
        (8000.0, "CASH"),
    ]
    assert all(p["creator"]["role"]["name"] == "VENDEUR" for p in history)


def test_overpayment_is_refused(client, headers, article):
    sale = create_sale(
        client, headers, article, payment={"method": "CARD", "amount": 15000}, payment_due_date=due_date()
    )
    response = pay(client, headers, sale.json()["id"], 5001, "CARD")
    assert response.status_code == 400 and response.json()["code"] == "INVALID_PAYMENT"


def test_initial_payment_above_total_is_refused(client, headers, article):
    response = create_sale(client, headers, article, payment={"method": "CARD", "amount": 20001})
    assert response.status_code == 400 and response.json()["code"] == "INVALID_PAYMENT"


def test_payment_after_paid_is_refused(client, headers, article):
    sale = create_sale(client, headers, article).json()
    response = pay(client, headers, sale["id"], 100, "CARD")
    assert response.status_code == 400 and response.json()["code"] == "PAYMENT_ALREADY_COMPLETED"


@pytest.mark.parametrize(("method", "amount"), [("CREDIT", 1000), ("CARD", 0), ("CARD", -10)])
def test_invalid_payment_input(client, headers, article, method, amount):
    sale = create_sale(client, headers, article, payment=None, payment_due_date=due_date()).json()
    assert pay(client, headers, sale["id"], amount, method).status_code == 422


def test_credit_with_an_amount_is_rejected(client, headers, article):
    response = create_sale(client, headers, article, payment={"method": "CREDIT", "amount": 5000})
    assert response.status_code == 422


def test_payment_on_cancelled_sale_is_refused(client, admin_headers, headers, article):
    sale = create_sale(client, headers, article, payment=None, payment_due_date=due_date()).json()
    client.post(f"/api/v1/sales/{sale['id']}/cancel", headers=admin_headers, json={"reason": "Annulée"})
    assert pay(client, admin_headers, sale["id"], 1000, "CARD").status_code == 400


def test_non_cash_payment_does_not_touch_cash_register(client, db, headers, article, register):
    create_sale(client, headers, article, payment={"method": "MOBILE_MONEY"})
    assert db.get(CashRegister, register.id).expected_amount == 0


def test_payment_is_audited(client, db, headers, article):
    sale = create_sale(client, headers, article, payment=None, payment_due_date=due_date()).json()
    pay(client, headers, sale["id"], 4000, "CARD")
    log = db.scalar(select(AuditLog).where(AuditLog.action == "payment.create"))
    assert log.new_data["amount"] == 4000.0 and log.new_data["remaining_amount"] == 16000.0


def test_vendeur_cannot_pay_a_sale_of_another_store(client, factory, admin_headers, headers):
    other = factory.product(selling_price="20000", stock=5)
    sale = client.post(
        "/api/v1/sales",
        headers=admin_headers,
        json=sale_payload((other, 1), payment=None, payment_due_date=due_date()),
    ).json()
    assert pay(client, headers, sale["id"], 1000, "CARD").status_code == 403
