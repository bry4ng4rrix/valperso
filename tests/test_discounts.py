from decimal import Decimal

import pytest
from sqlalchemy import select

from app.core.exceptions import BusinessRuleError
from app.core.permissions import RoleName
from app.models import AuditLog, CashTransaction
from app.models.enums import DiscountType
from app.services.discount_service import compute_discount
from tests.helpers import sale_payload

# --- Calcul (fonction pure) ----------------------------------------------------------------------


@pytest.mark.parametrize(
    ("discount_type", "value", "expected"),
    [
        (DiscountType.NONE, "0", "0"),
        (DiscountType.PERCENTAGE, "10", "10000"),
        (DiscountType.PERCENTAGE, "100", "100000"),
        (DiscountType.FIXED, "15000", "15000"),
        (DiscountType.FIXED, "100000", "100000"),
    ],
)
def test_compute_discount(discount_type, value, expected):
    assert compute_discount(Decimal("100000"), discount_type, Decimal(value)) == Decimal(expected)


def test_percentage_discount_is_rounded_to_the_cent():
    assert compute_discount(Decimal("100"), DiscountType.PERCENTAGE, Decimal("33.33")) == Decimal("33.33")
    assert compute_discount(Decimal("0.05"), DiscountType.PERCENTAGE, Decimal("50")) == Decimal("0.03")


@pytest.mark.parametrize(
    ("discount_type", "value"),
    [(DiscountType.PERCENTAGE, "100.01"), (DiscountType.FIXED, "100000.01"), (DiscountType.FIXED, "-1")],
    ids=["pourcentage-sup-100", "fixe-sup-sous-total", "negative"],
)
def test_invalid_discounts_are_refused(discount_type, value):
    with pytest.raises(BusinessRuleError):
        compute_discount(Decimal("100000"), discount_type, Decimal(value))


# --- Ventes avec réduction -----------------------------------------------------------------------


@pytest.fixture
def manager(factory):
    return factory.user(RoleName.MANAGER)


@pytest.fixture
def product(factory):
    return factory.product(selling_price="50000", stock=10)


# 5. Réduction en pourcentage
def test_sale_with_percentage_discount(client, factory, manager, product, db):
    payload = sale_payload((product, 2), discount_type="PERCENTAGE", discount_value=10)

    response = client.post("/api/v1/sales", headers=factory.headers(manager), json=payload)

    body = response.json()
    assert response.status_code == 201
    assert (body["subtotal"], body["discount_amount"], body["total"]) == (100000.0, 10000.0, 90000.0)
    assert body["payments"][0]["amount"] == 90000.0
    log = db.scalar(select(AuditLog).where(AuditLog.action == "sale.discount"))
    assert log.new_data == {"discount_type": "PERCENTAGE", "discount_value": 10.0, "discount_amount": 10000.0}


# 6. Réduction fixe
def test_sale_with_fixed_discount(client, factory, manager, product):
    payload = sale_payload((product, 2), discount_type="FIXED", discount_value=15000)
    body = client.post("/api/v1/sales", headers=factory.headers(manager), json=payload).json()
    assert (body["subtotal"], body["discount_amount"], body["total"]) == (100000.0, 15000.0, 85000.0)


# 7. Réduction supérieure au total
def test_fixed_discount_greater_than_subtotal_is_refused(client, factory, manager, product):
    payload = sale_payload((product, 2), discount_type="FIXED", discount_value=100001)

    response = client.post("/api/v1/sales", headers=factory.headers(manager), json=payload)

    assert response.status_code == 400
    assert response.json()["code"] == "DISCOUNT_EXCEEDS_SUBTOTAL"
    assert factory.store_quantity(factory.default_store(), product) == 10


@pytest.mark.parametrize(
    "fields",
    [
        {"discount_type": "PERCENTAGE", "discount_value": 101},
        {"discount_type": "PERCENTAGE", "discount_value": -5},
        {"discount_type": "FIXED", "discount_value": 0},
        {"discount_type": "NONE", "discount_value": 10},
    ],
    ids=["pourcentage-sup-100", "negative", "valeur-nulle", "valeur-sans-type"],
)
def test_invalid_discount_input_is_rejected(client, factory, manager, product, fields):
    response = client.post(
        "/api/v1/sales", headers=factory.headers(manager), json=sale_payload((product, 1), **fields)
    )
    assert response.status_code == 422


# 8. Utilisateur sans permission de réduction
def test_user_without_discount_permission_cannot_apply_discount(client, factory, product, db):
    vendeur = factory.user(RoleName.VENDEUR)
    payload = sale_payload((product, 2), discount_type="PERCENTAGE", discount_value=10)

    response = client.post("/api/v1/sales", headers=factory.headers(vendeur), json=payload)

    assert response.status_code == 403
    assert response.json()["code"] == "DISCOUNT_NOT_ALLOWED"
    assert factory.store_quantity(factory.default_store(), product) == 10
    without_discount = client.post(
        "/api/v1/sales", headers=factory.headers(vendeur), json=sale_payload((product, 2))
    )
    assert without_discount.status_code == 201


def test_full_discount_gives_a_free_sale_without_cash_movement(client, factory, manager, product, db):
    factory.open_register(factory.default_store(), manager)
    payload = sale_payload((product, 1), method="CASH", discount_type="PERCENTAGE", discount_value=100)

    body = client.post("/api/v1/sales", headers=factory.headers(manager), json=payload).json()

    assert body["total"] == 0.0 and body["amount_due"] == 0.0
    assert db.scalars(select(CashTransaction)).all() == []
