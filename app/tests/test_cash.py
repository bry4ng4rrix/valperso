from decimal import Decimal

import pytest
from sqlalchemy import func, select

from app.models import AuditLog, CashRegister, CashTransaction
from app.tests.helpers import due_date, sale_payload


def open_register(client, headers, amount=50000, **fields):
    return client.post("/api/v1/cash/registers/open", headers=headers, json={"opening_amount": amount, **fields})


def add_operation(client, headers, register_id, operation_type, amount, reason="Opération de test"):
    return client.post(
        f"/api/v1/cash/registers/{register_id}/transactions",
        headers=headers,
        json={"type": operation_type, "amount": amount, "reason": reason},
    )


def test_open_register_in_stock_local_by_default(client, factory, admin_headers, db):
    response = open_register(client, admin_headers)

    assert response.status_code == 201
    body = response.json()
    assert body["status"] == "OPEN" and body["store_id"] == factory.central_store().id
    assert body["opening_amount"] == body["expected_amount"] == 50000.0
    assert db.scalar(select(AuditLog).where(AuditLog.action == "cash.open"))


def test_only_one_open_register_per_store(client, factory, admin_headers):
    shop = factory.store()
    assert open_register(client, admin_headers).status_code == 201
    assert open_register(client, admin_headers, store_id=shop.id).status_code == 201
    response = open_register(client, admin_headers)
    assert response.status_code == 400 and response.json()["code"] == "CASH_REGISTER_ALREADY_OPEN"


def test_cash_payments_feed_the_register(client, factory, admin_headers):
    """Vente de 20 000 : avance de 10 000 le jour 1, solde de 10 000 le jour 2 -> caisse +20 000."""
    register_id = open_register(client, admin_headers, 0).json()["id"]
    product = factory.product(selling_price="20000", stock=5)
    sale = client.post(
        "/api/v1/sales",
        headers=admin_headers,
        json=sale_payload((product, 1), payment={"method": "CASH", "amount": 10000}, payment_due_date=due_date()),
    ).json()
    client.post(
        "/api/v1/payments", headers=admin_headers, json={"sale_id": sale["id"], "method": "CASH", "amount": 10000}
    )

    register = client.get(f"/api/v1/cash/registers/{register_id}", headers=admin_headers).json()
    operations = client.get(f"/api/v1/cash/registers/{register_id}/transactions", headers=admin_headers).json()

    assert register["expected_amount"] == 20000.0
    assert [(op["type"], op["amount"], op["reference"]) for op in operations["items"]] == [
        ("SALE", 10000.0, sale["sale_number"]),
        ("SALE", 10000.0, sale["sale_number"]),
    ]


def test_manual_operations_are_signed_by_type(client, admin_headers):
    register_id = open_register(client, admin_headers, 50000).json()["id"]

    amounts = [
        add_operation(client, admin_headers, register_id, kind, amount).json()["amount"]
        for kind, amount in [("EXPENSE", 5000), ("WITHDRAWAL", 20000), ("DEPOSIT", 1000), ("ADJUSTMENT", -500)]
    ]

    assert amounts == [-5000.0, -20000.0, 1000.0, -500.0]
    assert client.get(f"/api/v1/cash/registers/{register_id}", headers=admin_headers).json()["expected_amount"] == 25500.0


def test_expected_amount_equals_opening_plus_operations(client, factory, admin_headers, db):
    register_id = open_register(client, admin_headers, 10000).json()["id"]
    product = factory.product(selling_price="3000", stock=10)
    client.post("/api/v1/sales", headers=admin_headers, json=sale_payload((product, 3), payment={"method": "CASH"}))
    add_operation(client, admin_headers, register_id, "EXPENSE", 2500, "Transport")

    register = db.get(CashRegister, register_id)
    total = db.scalar(select(func.sum(CashTransaction.amount)).where(CashTransaction.cash_register_id == register_id))
    assert register.expected_amount == register.opening_amount + total == Decimal("16500")


def test_cash_cannot_become_negative(client, admin_headers):
    register_id = open_register(client, admin_headers, 1000).json()["id"]
    response = add_operation(client, admin_headers, register_id, "WITHDRAWAL", 1000.01, "Trop")
    assert response.status_code == 400 and response.json()["code"] == "INSUFFICIENT_CASH"


@pytest.mark.parametrize(
    ("operation_type", "amount"),
    [("SALE", 1000), ("REFUND", 1000), ("EXPENSE", -1000), ("DEPOSIT", 0)],
    ids=["sale-manuel", "refund-manuel", "montant-negatif", "montant-nul"],
)
def test_invalid_manual_operations_are_rejected(client, admin_headers, operation_type, amount):
    register_id = open_register(client, admin_headers).json()["id"]
    assert add_operation(client, admin_headers, register_id, operation_type, amount).status_code == 422


def test_close_register_computes_difference(client, admin, admin_headers):
    register_id = open_register(client, admin_headers, 50000).json()["id"]
    add_operation(client, admin_headers, register_id, "DEPOSIT", 10000, "Fond")

    body = client.post(
        f"/api/v1/cash/registers/{register_id}/close", headers=admin_headers, json={"closing_amount": 59500}
    ).json()

    assert body["status"] == "CLOSED" and body["closed_by"] == admin.id and body["closed_at"]
    assert (body["expected_amount"], body["closing_amount"], body["difference"]) == (60000.0, 59500.0, -500.0)


def test_closed_register_refuses_operations_and_second_closing(client, admin_headers):
    register_id = open_register(client, admin_headers).json()["id"]
    close_url = f"/api/v1/cash/registers/{register_id}/close"
    client.post(close_url, headers=admin_headers, json={"closing_amount": 50000})

    operation = add_operation(client, admin_headers, register_id, "DEPOSIT", 100)

    assert operation.status_code == 400 and operation.json()["code"] == "CASH_REGISTER_CLOSED"
    assert client.post(close_url, headers=admin_headers, json={"closing_amount": 50000}).status_code == 400
    assert open_register(client, admin_headers).status_code == 201


def test_current_register(client, admin_headers):
    assert client.get("/api/v1/cash/registers/current", headers=admin_headers).status_code == 404
    register_id = open_register(client, admin_headers).json()["id"]
    assert client.get("/api/v1/cash/registers/current", headers=admin_headers).json()["id"] == register_id


def test_vendeur_has_no_cash_access_by_default(client, factory):
    assert open_register(client, factory.headers(factory.vendeur(factory.store()))).status_code == 403
