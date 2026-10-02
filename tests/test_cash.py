from decimal import Decimal

import pytest
from sqlalchemy import func, select

from app.core.permissions import RoleName
from app.models import AuditLog, CashRegister, CashTransaction
from tests.helpers import sale_payload


@pytest.fixture
def caissier(factory):
    return factory.user(RoleName.CAISSIER)


def open_register(client, headers, amount=50000, **fields):
    return client.post(
        "/api/v1/cash/registers/open", headers=headers, json={"opening_amount": amount, **fields}
    )


def add_operation(client, headers, register_id, operation_type, amount, reason="Opération de test"):
    return client.post(
        f"/api/v1/cash/registers/{register_id}/transactions",
        headers=headers,
        json={"type": operation_type, "amount": amount, "reason": reason},
    )


def test_open_register_in_default_store(client, factory, caissier, db):
    response = open_register(client, factory.headers(caissier))

    assert response.status_code == 201
    body = response.json()
    assert body["status"] == "OPEN"
    assert body["store_id"] == factory.default_store().id
    assert body["opening_amount"] == body["expected_amount"] == 50000.0
    assert db.scalar(select(AuditLog).where(AuditLog.action == "cash.open"))


def test_only_one_open_register_per_store(client, factory, caissier):
    headers = factory.headers(caissier)
    open_register(client, headers)
    response = open_register(client, headers)
    assert response.status_code == 400
    assert response.json()["code"] == "CASH_REGISTER_ALREADY_OPEN"


def test_each_store_has_its_own_register(client, factory):
    shop = factory.store()
    admin_headers = factory.headers(factory.admin())
    assert open_register(client, admin_headers).status_code == 201
    assert open_register(client, admin_headers, store_id=shop.id).status_code == 201


def test_cash_sale_updates_expected_amount(client, factory, caissier, db):
    headers = factory.headers(caissier)
    register_id = open_register(client, headers, 50000).json()["id"]
    product = factory.product(selling_price="12500", stock=5)

    sale = client.post(
        "/api/v1/sales", headers=headers, json=sale_payload((product, 2), method="CASH")
    ).json()

    register = client.get(f"/api/v1/cash/registers/{register_id}", headers=headers).json()
    assert register["expected_amount"] == 75000.0
    operations = client.get(f"/api/v1/cash/registers/{register_id}/transactions", headers=headers).json()
    assert [(op["type"], op["amount"], op["reference"]) for op in operations["items"]] == [
        ("SALE", 25000.0, sale["sale_number"])
    ]


def test_manual_operations_are_signed_by_type(client, factory, caissier):
    headers = factory.headers(caissier)
    register_id = open_register(client, headers, 50000).json()["id"]

    expense = add_operation(client, headers, register_id, "EXPENSE", 5000, "Achat fournitures")
    withdrawal = add_operation(client, headers, register_id, "WITHDRAWAL", 20000, "Dépôt banque")
    deposit = add_operation(client, headers, register_id, "DEPOSIT", 1000, "Monnaie")
    adjustment = add_operation(client, headers, register_id, "ADJUSTMENT", -500, "Erreur de rendu")

    assert [r.json()["amount"] for r in (expense, withdrawal, deposit, adjustment)] == [
        -5000.0,
        -20000.0,
        1000.0,
        -500.0,
    ]
    register = client.get(f"/api/v1/cash/registers/{register_id}", headers=headers).json()
    assert register["expected_amount"] == 25500.0


def test_expected_amount_equals_opening_plus_operations(client, factory, caissier, db):
    headers = factory.headers(caissier)
    register_id = open_register(client, headers, 10000).json()["id"]
    product = factory.product(selling_price="3000", stock=10)
    client.post("/api/v1/sales", headers=headers, json=sale_payload((product, 3), method="CASH"))
    add_operation(client, headers, register_id, "EXPENSE", 2500, "Transport")

    register = db.get(CashRegister, register_id)
    total = db.scalar(
        select(func.sum(CashTransaction.amount)).where(CashTransaction.cash_register_id == register_id)
    )
    assert register.expected_amount == register.opening_amount + total == Decimal("16500")


def test_cash_cannot_become_negative(client, factory, caissier):
    headers = factory.headers(caissier)
    register_id = open_register(client, headers, 1000).json()["id"]

    response = add_operation(client, headers, register_id, "WITHDRAWAL", 1000.01, "Trop")

    assert response.status_code == 400
    assert response.json()["code"] == "INSUFFICIENT_CASH"


@pytest.mark.parametrize(
    ("operation_type", "amount"),
    [("SALE", 1000), ("REFUND", 1000), ("EXPENSE", -1000), ("DEPOSIT", 0)],
    ids=["sale-manuel", "refund-manuel", "montant-negatif", "montant-nul"],
)
def test_invalid_manual_operations_are_rejected(client, factory, caissier, operation_type, amount):
    headers = factory.headers(caissier)
    register_id = open_register(client, headers).json()["id"]
    assert add_operation(client, headers, register_id, operation_type, amount).status_code == 422


def test_close_register_computes_difference(client, factory, caissier):
    headers = factory.headers(caissier)
    register_id = open_register(client, headers, 50000).json()["id"]
    add_operation(client, headers, register_id, "DEPOSIT", 10000, "Fond")

    response = client.post(
        f"/api/v1/cash/registers/{register_id}/close", headers=headers, json={"closing_amount": 59500}
    )

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "CLOSED" and body["closed_by"] == caissier.id and body["closed_at"]
    assert body["expected_amount"] == 60000.0
    assert body["closing_amount"] == 59500.0
    assert body["difference"] == -500.0


def test_closed_register_refuses_operations_and_second_closing(client, factory, caissier):
    headers = factory.headers(caissier)
    register_id = open_register(client, headers).json()["id"]
    client.post(
        f"/api/v1/cash/registers/{register_id}/close", headers=headers, json={"closing_amount": 50000}
    )

    operation = add_operation(client, headers, register_id, "DEPOSIT", 100)
    second_close = client.post(
        f"/api/v1/cash/registers/{register_id}/close", headers=headers, json={"closing_amount": 50000}
    )

    assert operation.status_code == 400 and operation.json()["code"] == "CASH_REGISTER_CLOSED"
    assert second_close.status_code == 400
    assert open_register(client, headers).status_code == 201  # une nouvelle caisse peut être ouverte


def test_current_register(client, factory, caissier):
    headers = factory.headers(caissier)
    assert client.get("/api/v1/cash/registers/current", headers=headers).status_code == 404
    register_id = open_register(client, headers).json()["id"]
    assert client.get("/api/v1/cash/registers/current", headers=headers).json()["id"] == register_id


def test_store_user_cannot_use_another_store_register(client, factory):
    other_register = factory.open_register(factory.default_store(), factory.admin())
    caissier = factory.user(RoleName.CAISSIER, factory.store())

    response = add_operation(client, factory.headers(caissier), other_register.id, "DEPOSIT", 100)

    assert response.status_code == 403


def test_vendeur_cannot_open_register(client, factory):
    assert open_register(client, factory.headers(factory.user(RoleName.VENDEUR))).status_code == 403
