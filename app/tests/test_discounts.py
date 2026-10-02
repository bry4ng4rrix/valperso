from decimal import Decimal

import pytest
from sqlalchemy import select

from app.core.exceptions import InvalidDiscount
from app.models import AuditLog
from app.models.enums import DiscountType
from app.services.discount_service import compute_discount
from app.tests.helpers import sale_payload


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


@pytest.mark.parametrize(
    ("discount_type", "value"),
    [(DiscountType.PERCENTAGE, "100.01"), (DiscountType.FIXED, "100000.01"), (DiscountType.FIXED, "-1")],
    ids=["pourcentage-sup-100", "fixe-sup-sous-total", "negative"],
)
def test_invalid_discounts_are_refused(discount_type, value):
    with pytest.raises(InvalidDiscount):
        compute_discount(Decimal("100000"), discount_type, Decimal(value))


@pytest.fixture
def product(factory):
    return factory.product(selling_price="50000", stock=10)


def test_percentage_discount(client, admin_headers, product, db):
    payload = sale_payload((product, 2), discount_type="PERCENTAGE", discount_value=10)

    body = client.post("/api/v1/sales", headers=admin_headers, json=payload).json()

    assert (body["subtotal"], body["discount_amount"], body["total"]) == (100000.0, 10000.0, 90000.0)
    assert body["amount_paid"] == 90000.0
    log = db.scalar(select(AuditLog).where(AuditLog.action == "sale.discount"))
    assert log.new_data == {"discount_type": "PERCENTAGE", "discount_value": 10.0, "discount_amount": 10000.0}


def test_fixed_discount(client, admin_headers, product):
    payload = sale_payload((product, 2), discount_type="FIXED", discount_value=15000)
    body = client.post("/api/v1/sales", headers=admin_headers, json=payload).json()
    assert (body["subtotal"], body["discount_amount"], body["total"]) == (100000.0, 15000.0, 85000.0)


def test_fixed_discount_greater_than_subtotal_is_refused(client, factory, admin_headers, product):
    payload = sale_payload((product, 2), discount_type="FIXED", discount_value=100001)

    response = client.post("/api/v1/sales", headers=admin_headers, json=payload)

    assert response.status_code == 400 and response.json()["code"] == "INVALID_DISCOUNT"
    assert factory.quantity(factory.central_store(), product) == 10


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
def test_invalid_discount_input_is_rejected(client, admin_headers, product, fields):
    response = client.post("/api/v1/sales", headers=admin_headers, json=sale_payload((product, 1), **fields))
    assert response.status_code == 422


def test_vendeur_without_discount_permission(client, factory):
    shop = factory.store()
    product = factory.product(selling_price="50000", stock=10, store=shop)
    headers = factory.headers(factory.vendeur(shop))
    payload = sale_payload((product, 2), discount_type="PERCENTAGE", discount_value=10)

    response = client.post("/api/v1/sales", headers=headers, json=payload)

    assert response.status_code == 403 and response.json()["code"] == "DISCOUNT_NOT_ALLOWED"
    assert factory.quantity(shop, product) == 10
    assert client.post("/api/v1/sales", headers=headers, json=sale_payload((product, 2))).status_code == 201
