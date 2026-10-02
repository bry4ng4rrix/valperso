"""Échéancier des ventes avec dette : plusieurs dates de remboursement, chacune avec son montant."""

from datetime import date, timedelta

import pytest
from sqlalchemy import update

from app.models import SaleInstallment
from app.tests.helpers import due_date, sale_payload


@pytest.fixture
def shop(factory):
    return factory.store()


@pytest.fixture
def headers(factory, shop):
    return factory.headers(factory.vendeur(shop))


@pytest.fixture
def article(factory, shop):
    return factory.product(selling_price="120000", stock=10, store=shop)  # total d'une vente : 120 000 Ar


def create_sale(client, headers, article, payment=None, **fields):
    return client.post(
        "/api/v1/sales", headers=headers, json=sale_payload((article, 1), payment=payment, **fields)
    )


def schedule(*lines: tuple[int, int]) -> list[dict]:
    """[(jours à partir d'aujourd'hui, montant), ...]"""
    return [{"due_date": due_date(days), "amount": amount} for days, amount in lines]


def pay(client, headers, sale_id, amount):
    return client.post(
        "/api/v1/payments", headers=headers, json={"sale_id": sale_id, "method": "CASH", "amount": amount}
    )


def states(sale: dict) -> list[tuple]:
    return [(i["due_date"], i["amount"], i["remaining_amount"], i["status"]) for i in sale["installments"]]


def test_advance_then_two_repayment_dates(client, headers, article):
    """Avance de 20 000 sur 120 000, puis 50 000 dans 10 jours et 50 000 dans 20 jours."""
    response = create_sale(
        client,
        headers,
        article,
        payment={"method": "CASH", "amount": 20000},
        installments=schedule((20, 50000), (10, 50000)),  # l'ordre d'envoi n'a pas d'importance
    )

    assert response.status_code == 201, response.json()
    sale = response.json()
    assert sale["payment_due_date"] == due_date(10), "prochaine échéance"
    assert states(sale) == [
        (due_date(10), 50000.0, 50000.0, "UNPAID"),
        (due_date(20), 50000.0, 50000.0, "UNPAID"),
    ]
    assert not any(i["is_overdue"] for i in sale["installments"])


def test_payments_settle_installments_in_date_order(client, headers, article):
    sale = create_sale(client, headers, article, installments=schedule((10, 70000), (20, 50000))).json()

    pay(client, headers, sale["id"], 30000)
    partial = client.get(f"/api/v1/sales/{sale['id']}", headers=headers).json()
    assert states(partial) == [
        (due_date(10), 70000.0, 40000.0, "PARTIAL"),
        (due_date(20), 50000.0, 50000.0, "UNPAID"),
    ]
    assert partial["payment_due_date"] == due_date(10)

    pay(client, headers, sale["id"], 40000)
    first_paid = client.get(f"/api/v1/sales/{sale['id']}", headers=headers).json()
    assert [i["status"] for i in first_paid["installments"]] == ["PAID", "UNPAID"]
    assert first_paid["installments"][0]["paid_amount"] == 70000.0
    assert first_paid["payment_due_date"] == due_date(20), "l'échéance affichée passe à la suivante"

    pay(client, headers, sale["id"], 50000)
    paid = client.get(f"/api/v1/sales/{sale['id']}", headers=headers).json()
    assert paid["payment_status"] == "PAID"
    assert [i["status"] for i in paid["installments"]] == ["PAID", "PAID"]


def test_installments_must_add_up_to_the_remaining_amount(client, headers, article):
    response = create_sale(
        client,
        headers,
        article,
        payment={"method": "CASH", "amount": 20000},
        installments=schedule((10, 50000), (20, 40000)),
    )
    assert response.status_code == 400 and response.json()["code"] == "INVALID_PAYMENT"
    assert "100000" in response.json()["detail"]


@pytest.mark.parametrize(
    "installments",
    [
        schedule((10, 60000), (10, 60000)),  # même date deux fois
        [{"due_date": (date.today() - timedelta(days=1)).isoformat(), "amount": 120000}],  # date passée
        schedule((10, 120000), (20, 0)),  # montant nul
    ],
)
def test_invalid_installments_are_rejected(client, headers, article, installments):
    assert create_sale(client, headers, article, installments=installments).status_code == 422


def test_single_due_date_becomes_one_installment(client, headers, article):
    sale = create_sale(
        client, headers, article, payment={"method": "CASH", "amount": 20000}, payment_due_date=due_date(15)
    ).json()
    assert states(sale) == [(due_date(15), 100000.0, 100000.0, "UNPAID")]


def test_a_debt_needs_a_date(client, headers, article):
    response = create_sale(client, headers, article)
    assert response.status_code == 400 and "installments" in response.json()["detail"]


def test_full_payment_has_no_installments(client, headers, article):
    sale = create_sale(
        client, headers, article, payment={"method": "CASH"}, installments=schedule((10, 120000))
    ).json()
    assert sale["installments"] == [] and sale["payment_due_date"] is None


def test_overdue_installment(client, db, headers, article):
    sale = create_sale(client, headers, article, installments=schedule((10, 60000), (20, 60000))).json()
    db.execute(
        update(SaleInstallment)
        .where(SaleInstallment.due_date == date.fromisoformat(due_date(10)))
        .values(due_date=date.today() - timedelta(days=2))
    )
    db.commit()

    body = client.get(f"/api/v1/sales/{sale['id']}", headers=headers).json()

    assert [i["is_overdue"] for i in body["installments"]] == [True, False]


def test_invoice_and_customer_debts_show_the_schedule(client, headers, article):
    sale = create_sale(client, headers, article, installments=schedule((10, 60000), (20, 60000))).json()

    invoice = client.get(f"/api/v1/sales/{sale['id']}/invoice", headers=headers).json()
    debts = client.get(f"/api/v1/customers/{sale['customer']['id']}/debts", headers=headers).json()

    assert [i["amount"] for i in invoice["installments"]] == [60000.0, 60000.0]
    assert [i["due_date"] for i in debts["sales"][0]["installments"]] == [due_date(10), due_date(20)]
