import re

import pytest
from sqlalchemy import func, select

from app.models import AuditLog, CashTransaction, Customer, Payment, Sale, SaleItem, StockMovement
from app.services import audit_service
from app.tests.helpers import CUSTOMER, sale_payload


def count(db, model) -> int:
    return db.scalar(select(func.count()).select_from(model))


@pytest.fixture
def shop(factory):
    return factory.store("Magasin 1")


@pytest.fixture
def seller(factory, shop):
    return factory.vendeur(shop, first_name="Jean", username="jean.vendeur")


@pytest.fixture
def seller_headers(factory, seller):
    return factory.headers(seller)


def test_sale_is_created_with_backend_computed_amounts(client, factory, shop, seller_headers):
    riz = factory.product(selling_price="3200", stock=10, store=shop)
    huile = factory.product(selling_price="8500", stock=5, store=shop)

    response = client.post("/api/v1/sales", headers=seller_headers, json=sale_payload((riz, 3), (huile, 1)))

    assert response.status_code == 201
    body = response.json()
    assert (body["subtotal"], body["discount_amount"], body["total"]) == (18100.0, 0.0, 18100.0)
    assert [(i["quantity"], i["unit_price"], i["total"]) for i in body["items"]] == [
        (3, 3200.0, 9600.0),
        (1, 8500.0, 8500.0),
    ]
    assert re.fullmatch(r"FAC-\d{4}-\d{6}", body["sale_number"])
    assert (body["payment_status"], body["amount_paid"], body["remaining_amount"]) == ("PAID", 18100.0, 0.0)


def test_sale_belongs_to_connected_user_and_his_store(
    client, factory, admin, shop, seller, seller_headers, db
):
    product = factory.product(stock=5, store=shop)
    payload = sale_payload((product, 1), user_id=admin.id)  # tentative de choisir un autre vendeur : ignorée

    body = client.post("/api/v1/sales", headers=seller_headers, json=payload).json()

    assert body["user"]["id"] == seller.id and body["user"]["role"]["name"] == "VENDEUR"
    assert body["store"]["id"] == shop.id
    sale = db.get(Sale, body["id"])
    assert (sale.user_id, sale.store_id) == (seller.id, shop.id)


def test_admin_sale_is_linked_to_admin_and_stock_local_by_default(client, factory, admin, admin_headers):
    product = factory.product(stock=5)
    body = client.post("/api/v1/sales", headers=admin_headers, json=sale_payload((product, 1))).json()
    assert body["user"]["id"] == admin.id and body["store"]["is_central"] is True


def test_insufficient_stock(client, factory, shop, seller_headers, db):
    product = factory.product(stock=2, store=shop)

    response = client.post("/api/v1/sales", headers=seller_headers, json=sale_payload((product, 5)))

    assert response.status_code == 400 and response.json()["code"] == "INSUFFICIENT_STOCK"
    assert count(db, Sale) == 0


def test_only_the_sale_store_stock_is_used(client, factory, seller_headers):
    product = factory.product(stock=10)  # uniquement au Stock Local
    response = client.post("/api/v1/sales", headers=seller_headers, json=sale_payload((product, 1)))
    assert response.status_code == 400 and response.json()["code"] == "INSUFFICIENT_STOCK"


def test_inactive_product_cannot_be_sold(client, factory, shop, seller_headers):
    product = factory.product(stock=5, store=shop, is_active=False)
    response = client.post("/api/v1/sales", headers=seller_headers, json=sale_payload((product, 1)))
    assert response.status_code == 400 and response.json()["code"] == "INACTIVE_PRODUCT"


def test_product_snapshot_is_kept_after_product_change(client, factory, shop, seller_headers, db):
    product = factory.product(name="Savon", reference="SAV-1", selling_price="1000", stock=5, store=shop)
    sale = client.post("/api/v1/sales", headers=seller_headers, json=sale_payload((product, 1))).json()

    product.name, product.reference, product.selling_price = "Savon Nouveau", "SAV-2", 9999
    db.commit()

    item = client.get(f"/api/v1/sales/{sale['id']}", headers=seller_headers).json()["items"][0]
    assert (item["product_name"], item["product_reference"], item["unit_price"]) == ("savon", "sav-1", 1000.0)


def test_stock_is_deducted_and_sale_movement_created(client, factory, shop, seller, seller_headers, db):
    product = factory.product(stock=10, store=shop)

    sale = client.post("/api/v1/sales", headers=seller_headers, json=sale_payload((product, 3))).json()

    assert factory.quantity(shop, product) == 7
    movement = db.scalar(select(StockMovement).where(StockMovement.product_id == product.id))
    assert (movement.type, movement.quantity, movement.store_id, movement.user_id) == (
        "SALE",
        -3,
        shop.id,
        seller.id,
    )
    assert movement.reference == sale["sale_number"]


def test_customer_is_created_once_and_reused(client, factory, shop, seller_headers, db):
    product = factory.product(stock=10, store=shop)
    first = client.post("/api/v1/sales", headers=seller_headers, json=sale_payload((product, 1))).json()
    second = client.post("/api/v1/sales", headers=seller_headers, json=sale_payload((product, 1))).json()

    assert first["customer"]["id"] == second["customer"]["id"]
    assert first["customer"]["first_name"] == "jean" and first["customer"]["phone"] == CUSTOMER["phone"]
    assert count(db, Customer) == 1


def test_existing_customer_by_id(client, factory, shop, seller_headers):
    customer = factory.customer("Rasoa", "Vola")
    product = factory.product(stock=10, store=shop)
    body = client.post(
        "/api/v1/sales", headers=seller_headers, json=sale_payload((product, 1), customer=customer)
    ).json()
    assert body["customer"]["id"] == customer.id


@pytest.mark.parametrize(
    "customer",
    [{"first_name": "Jean"}, {"last_name": "Rakoto"}, {"first_name": "", "last_name": "Rakoto"}],
    ids=["sans-nom", "sans-prenom", "prenom-vide"],
)
def test_customer_first_and_last_names_are_required(client, factory, shop, seller_headers, customer):
    product = factory.product(stock=10, store=shop)
    response = client.post(
        "/api/v1/sales", headers=seller_headers, json=sale_payload((product, 1), customer=customer)
    )
    assert response.status_code == 422


def test_fully_paid_sale_does_not_require_a_phone(client, factory, shop, seller_headers):
    product = factory.product(stock=10, store=shop)
    payload = sale_payload((product, 1), customer={"first_name": "Paul", "last_name": "Rabe"})
    assert client.post("/api/v1/sales", headers=seller_headers, json=payload).status_code == 201


def test_rollback_when_cash_register_is_closed(client, factory, shop, seller_headers, db):
    """L'erreur survient à l'étape caisse, après la création de la vente, du client
    et la déduction du stock."""
    product = factory.product(stock=10, store=shop)

    response = client.post(
        "/api/v1/sales", headers=seller_headers, json=sale_payload((product, 3), payment={"method": "CASH"})
    )

    assert response.status_code == 400 and response.json()["code"] == "CASH_REGISTER_CLOSED"
    assert count(db, Sale) == count(db, SaleItem) == count(db, Payment) == count(db, StockMovement) == 0
    assert count(db, Customer) == 0
    assert factory.quantity(shop, product) == 10


def test_rollback_when_an_unexpected_error_occurs(client, factory, shop, seller_headers, db, monkeypatch):
    product = factory.product(stock=10, store=shop)

    def broken_audit(*args, **kwargs):
        raise RuntimeError("panne simulée")

    monkeypatch.setattr(audit_service, "record", broken_audit)
    with pytest.raises(RuntimeError, match="panne simulée"):
        client.post("/api/v1/sales", headers=seller_headers, json=sale_payload((product, 3)))

    assert count(db, Sale) == count(db, Payment) == count(db, StockMovement) == 0
    assert factory.quantity(shop, product) == 10


def test_cancel_sale_restores_stock_and_refunds_cash(
    client, factory, admin_headers, shop, seller, seller_headers, db
):
    register = factory.open_register(shop, seller, "10000")
    product = factory.product(selling_price="2000", stock=10, store=shop)
    sale = client.post(
        "/api/v1/sales", headers=seller_headers, json=sale_payload((product, 4), payment={"method": "CASH"})
    ).json()

    response = client.post(
        f"/api/v1/sales/{sale['id']}/cancel", headers=admin_headers, json={"reason": "Erreur"}
    )
    again = client.post(
        f"/api/v1/sales/{sale['id']}/cancel", headers=admin_headers, json={"reason": "Erreur"}
    )

    assert response.status_code == 200 and response.json()["status"] == "CANCELLED"
    assert again.status_code == 400 and again.json()["code"] == "SALE_ALREADY_CANCELLED"
    assert factory.quantity(shop, product) == 10
    returns = db.scalars(select(StockMovement).where(StockMovement.type == "RETURN")).all()
    assert [(m.quantity, m.reference) for m in returns] == [(4, sale["sale_number"])]
    db.refresh(register)
    assert register.expected_amount == 10000  # +8000 encaissés puis -8000 remboursés
    assert db.scalar(select(CashTransaction).where(CashTransaction.type == "REFUND")).amount == -8000
    assert (
        db.scalar(select(AuditLog).where(AuditLog.action == "sale.cancel")).new_data["cancel_reason"]
        == "ERREUR"
    )


def test_vendeur_cannot_cancel_by_default(client, factory, shop, seller_headers):
    product = factory.product(stock=5, store=shop)
    sale_id = client.post("/api/v1/sales", headers=seller_headers, json=sale_payload((product, 1))).json()[
        "id"
    ]
    response = client.post(f"/api/v1/sales/{sale_id}/cancel", headers=seller_headers, json={"reason": "Test"})
    assert response.status_code == 403


@pytest.mark.parametrize(
    "items",
    [
        [],
        [{"product_id": 1, "quantity": 0}],
        [{"product_id": 1, "quantity": 1}, {"product_id": 1, "quantity": 2}],
    ],
    ids=["sans-ligne", "quantite-nulle", "produit-en-double"],
)
def test_invalid_sale_lines_are_rejected(client, seller_headers, items):
    payload = {"items": items, "customer": CUSTOMER, "payment": {"method": "CARD"}}
    assert client.post("/api/v1/sales", headers=seller_headers, json=payload).status_code == 422


# --- Historique et facture -----------------------------------------------------------------------


@pytest.fixture
def history(client, factory, admin_headers, shop, seller_headers):
    """Trois ventes : deux dans le magasin 1 (dont une avec dette), une au Stock Local par l'ADMIN."""
    product = factory.product(selling_price="10000", stock=10, store=shop)
    factory.add_stock(product, 10)
    paid = client.post("/api/v1/sales", headers=seller_headers, json=sale_payload((product, 1))).json()
    debt = client.post(
        "/api/v1/sales",
        headers=seller_headers,
        json=sale_payload(
            (product, 2),
            customer={"first_name": "Rasoa", "last_name": "Vola", "phone": "0329998877"},
            payment={"method": "MOBILE_MONEY", "amount": 5000},
            payment_due_date="2099-01-31",
        ),
    ).json()
    admin_sale = client.post("/api/v1/sales", headers=admin_headers, json=sale_payload((product, 1))).json()
    return {"paid": paid, "debt": debt, "admin_sale": admin_sale}


def test_history_search_and_filters(client, admin_headers, history, seller, shop):
    def numbers(**params):
        items = client.get("/api/v1/sales/history", headers=admin_headers, params=params).json()["items"]
        return {item["sale_number"] for item in items}

    assert numbers() == {history[key]["sale_number"] for key in history}
    assert numbers(user_id=seller.id) == {history["paid"]["sale_number"], history["debt"]["sale_number"]}
    assert numbers(store_id=shop.id) == {history["paid"]["sale_number"], history["debt"]["sale_number"]}
    assert numbers(payment_status="PARTIAL") == {history["debt"]["sale_number"]}
    assert numbers(has_debt=True) == {history["debt"]["sale_number"]}
    assert numbers(search="0329998877") == {history["debt"]["sale_number"]}
    assert numbers(search="rasoa") == {history["debt"]["sale_number"]}
    assert numbers(search=history["paid"]["sale_number"]) == {history["paid"]["sale_number"]}


def test_history_row_contains_everything(client, admin_headers, history):
    rows = client.get("/api/v1/sales/history", headers=admin_headers, params={"has_debt": True}).json()[
        "items"
    ]
    row = rows[0]
    assert row["customer"] == {
        **row["customer"],
        "first_name": "rasoa",
        "last_name": "vola",
        "phone": "0329998877",
    }
    assert row["user"]["role"]["name"] == "VENDEUR" and row["store"]["name"] == "magasin 1"
    assert (row["total"], row["amount_paid"], row["remaining_amount"]) == (20000.0, 5000.0, 15000.0)
    assert row["payment_due_date"] == "2099-01-31"


def test_vendeur_history_is_limited_to_his_store(client, seller_headers, history):
    items = client.get("/api/v1/sales/history", headers=seller_headers).json()["items"]
    assert history["admin_sale"]["id"] not in {item["id"] for item in items}
    assert (
        client.get(f"/api/v1/sales/{history['admin_sale']['id']}", headers=seller_headers).status_code == 403
    )


def test_invoice(client, seller_headers, history):
    response = client.get(f"/api/v1/sales/{history['debt']['id']}/invoice", headers=seller_headers)

    assert response.status_code == 200
    invoice = response.json()
    assert invoice["invoice_number"] == history["debt"]["sale_number"] and invoice["date"]
    assert invoice["store"]["name"] == "magasin 1"
    assert invoice["user"]["first_name"] == "jean" and invoice["user"]["role"]["name"] == "VENDEUR"
    assert invoice["customer"]["phone"] == "0329998877"
    assert [(line["quantity"], line["unit_price"], line["total"]) for line in invoice["lines"]] == [
        (2, 10000.0, 20000.0)
    ]
    assert invoice["lines"][0]["product_reference"]
    assert (invoice["total"], invoice["amount_paid"], invoice["remaining_amount"]) == (
        20000.0,
        5000.0,
        15000.0,
    )
    assert invoice["payment_status"] == "PARTIAL" and invoice["payment_due_date"] == "2099-01-31"
    assert [p["amount"] for p in invoice["payments"]] == [5000.0]
