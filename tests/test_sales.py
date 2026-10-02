import re

import pytest
from sqlalchemy import func, select

from app.core.permissions import RoleName
from app.models import AuditLog, CashTransaction, Payment, Product, Sale, SaleItem, StockMovement
from app.services import audit_service
from tests.helpers import sale_payload


def count(db, model) -> int:
    return db.scalar(select(func.count()).select_from(model))


@pytest.fixture
def seller(factory):
    """Vendeur non rattaché à un magasin : il vend depuis le STOCK LOCAL."""
    return factory.user(RoleName.VENDEUR)


# 1. Vente avec stock suffisant
def test_sale_with_sufficient_stock(client, factory, seller):
    riz = factory.product(selling_price="3200", stock=10)
    huile = factory.product(selling_price="8500", stock=5)

    response = client.post(
        "/api/v1/sales", headers=factory.headers(seller), json=sale_payload((riz, 3), (huile, 1))
    )

    assert response.status_code == 201
    body = response.json()
    assert body["status"] == "COMPLETED"
    assert body["subtotal"] == 18100.0 and body["discount_amount"] == 0.0 and body["total"] == 18100.0
    assert [(i["quantity"], i["unit_price"], i["total"]) for i in body["items"]] == [
        (3, 3200.0, 9600.0),
        (1, 8500.0, 8500.0),
    ]
    assert re.fullmatch(r"v\d{8}-\d{6}", body["sale_number"])
    assert body["payments"][0]["method"] == "MOBILE_MONEY" and body["payments"][0]["amount"] == 18100.0
    assert body["amount_paid"] == 18100.0 and body["amount_due"] == 0.0


# 2. Vente avec stock insuffisant
def test_sale_with_insufficient_stock_is_refused(client, factory, seller, db):
    product = factory.product(stock=2)

    response = client.post("/api/v1/sales", headers=factory.headers(seller), json=sale_payload((product, 5)))

    assert response.status_code == 400
    assert response.json()["code"] == "INSUFFICIENT_STOCK"
    assert "disponible 2, demandé 5" in response.json()["detail"]
    assert count(db, Sale) == 0


# 3. Vente sans client
def test_sale_without_customer(client, factory, seller, db):
    product = factory.product(stock=5)
    response = client.post("/api/v1/sales", headers=factory.headers(seller), json=sale_payload((product, 1)))
    assert response.status_code == 201
    assert response.json()["customer_name"] is None
    assert db.get(Sale, response.json()["id"]).customer_name is None


# 4. Vente avec nom client
def test_sale_with_customer_name(client, factory, seller, db):
    product = factory.product(stock=5)

    response = client.post(
        "/api/v1/sales",
        headers=factory.headers(seller),
        json=sale_payload((product, 1), customer_name="Jean"),
    )

    assert response.json()["customer_name"] == "jean"
    assert db.get(Sale, response.json()["id"]).customer_name == "JEAN"


def test_blank_customer_name_is_stored_as_null(client, factory, seller):
    product = factory.product(stock=5)
    response = client.post(
        "/api/v1/sales", headers=factory.headers(seller), json=sale_payload((product, 1), customer_name="   ")
    )
    assert response.json()["customer_name"] is None


# 9. Annulation de vente
def test_cancel_sale_restores_stock_and_refunds_cash(client, factory, db):
    caissier = factory.user(RoleName.CAISSIER)
    manager = factory.user(RoleName.MANAGER)
    register = factory.open_register(factory.default_store(), caissier, "10000")
    product = factory.product(selling_price="2000", stock=10)
    sale = client.post(
        "/api/v1/sales", headers=factory.headers(caissier), json=sale_payload((product, 4), method="CASH")
    ).json()

    response = client.post(
        f"/api/v1/sales/{sale['id']}/cancel",
        headers=factory.headers(manager),
        json={"reason": "Erreur de caisse"},
    )

    assert response.status_code == 200
    assert response.json()["status"] == "CANCELLED"
    db.refresh(product)
    db.refresh(register)
    assert product.stock == 10
    assert factory.store_quantity(factory.default_store(), product) == 10
    returns = db.scalars(select(StockMovement).where(StockMovement.type == "RETURN")).all()
    assert [(m.quantity, m.reference) for m in returns] == [(4, sale["sale_number"].upper())]
    assert register.expected_amount == 10000  # +8000 (vente) -8000 (remboursement)
    refund = db.scalar(select(CashTransaction).where(CashTransaction.type == "REFUND"))
    assert refund.amount == -8000
    log = db.scalar(select(AuditLog).where(AuditLog.action == "sale.cancel"))
    assert log.new_data["cancel_reason"] == "ERREUR DE CAISSE"


def test_sale_cannot_be_cancelled_twice(client, factory, seller):
    product = factory.product(stock=5)
    sale_id = client.post(
        "/api/v1/sales", headers=factory.headers(seller), json=sale_payload((product, 1))
    ).json()["id"]
    headers = factory.headers(factory.admin())

    client.post(f"/api/v1/sales/{sale_id}/cancel", headers=headers, json={"reason": "Test"})
    response = client.post(f"/api/v1/sales/{sale_id}/cancel", headers=headers, json={"reason": "Test"})

    assert response.status_code == 400
    assert response.json()["code"] == "SALE_ALREADY_CANCELLED"


def test_vendeur_cannot_cancel_a_sale(client, factory, seller):
    product = factory.product(stock=5)
    headers = factory.headers(seller)
    sale_id = client.post("/api/v1/sales", headers=headers, json=sale_payload((product, 1))).json()["id"]
    assert (
        client.post(f"/api/v1/sales/{sale_id}/cancel", headers=headers, json={"reason": "Test"}).status_code
        == 403
    )


# 10. Mise à jour correcte du stock
def test_sale_updates_store_stock_and_product_total(client, factory, seller, db):
    shop = factory.store()
    product = factory.product(stock=10)  # STOCK LOCAL
    factory.add_stock(product, 6, shop)
    shop_seller = factory.user(RoleName.VENDEUR, shop)

    client.post("/api/v1/sales", headers=factory.headers(shop_seller), json=sale_payload((product, 4)))

    assert factory.store_quantity(shop, product) == 2
    assert factory.store_quantity(factory.default_store(), product) == 10
    db.refresh(product)
    assert product.stock == 12


def test_sale_uses_only_the_stock_of_the_sale_store(client, factory):
    shop = factory.store()
    product = factory.product(stock=10)  # uniquement au STOCK LOCAL
    shop_seller = factory.user(RoleName.VENDEUR, shop)

    response = client.post(
        "/api/v1/sales", headers=factory.headers(shop_seller), json=sale_payload((product, 1))
    )

    assert response.status_code == 400
    assert response.json()["code"] == "INSUFFICIENT_STOCK"


# 11. Création du mouvement de stock
def test_sale_creates_sale_stock_movement(client, factory, seller, db):
    product = factory.product(stock=10)

    sale = client.post(
        "/api/v1/sales", headers=factory.headers(seller), json=sale_payload((product, 3))
    ).json()

    movement = db.scalar(select(StockMovement).where(StockMovement.product_id == product.id))
    assert movement.type == "SALE"
    assert movement.quantity == -3
    assert movement.store_id == factory.default_store().id
    assert movement.user_id == seller.id
    assert movement.reference == sale["sale_number"].upper()


# 12. Rollback de la transaction en cas d'erreur
def test_cash_sale_without_open_register_rolls_back_everything(client, factory, seller, db):
    """L'erreur survient à l'étape caisse, après la création de la vente et la déduction du stock."""
    product = factory.product(stock=10)

    response = client.post(
        "/api/v1/sales", headers=factory.headers(seller), json=sale_payload((product, 3), method="CASH")
    )

    assert response.status_code == 400
    assert response.json()["code"] == "NO_OPEN_CASH_REGISTER"
    assert count(db, Sale) == count(db, SaleItem) == count(db, Payment) == count(db, StockMovement) == 0
    db.refresh(product)
    assert product.stock == 10
    assert factory.store_quantity(factory.default_store(), product) == 10


def test_unexpected_error_during_sale_rolls_back_everything(client, factory, seller, db, monkeypatch):
    """Panne à la toute dernière étape (audit) : rien ne doit rester en base."""
    product = factory.product(stock=10)

    def broken_audit(*args, **kwargs):
        raise RuntimeError("panne simulée")

    monkeypatch.setattr(audit_service, "record", broken_audit)

    with pytest.raises(RuntimeError, match="panne simulée"):
        client.post("/api/v1/sales", headers=factory.headers(seller), json=sale_payload((product, 3)))

    assert count(db, Sale) == count(db, SaleItem) == count(db, Payment) == count(db, StockMovement) == 0
    assert db.get(Product, product.id).stock == 10


# Calculs et validations
def test_total_sent_by_client_is_ignored(client, factory, seller):
    product = factory.product(selling_price="1000", stock=5)
    response = client.post(
        "/api/v1/sales",
        headers=factory.headers(seller),
        json=sale_payload((product, 2), total=1, subtotal=1, items_total=1),
    )
    assert response.json()["total"] == 2000.0


def test_sale_price_is_copied_and_kept_after_product_change(client, factory, seller, db):
    product = factory.product(name="Savon", selling_price="1000", stock=5)
    sale = client.post(
        "/api/v1/sales", headers=factory.headers(seller), json=sale_payload((product, 1))
    ).json()

    product.name = "Savon Nouveau"
    product.selling_price = 9999
    db.commit()

    item = client.get(f"/api/v1/sales/{sale['id']}", headers=factory.headers(seller)).json()["items"][0]
    assert item["product_name"] == "savon" and item["unit_price"] == 1000.0


def test_inactive_product_cannot_be_sold(client, factory, seller):
    product = factory.product(stock=5, is_active=False)
    response = client.post("/api/v1/sales", headers=factory.headers(seller), json=sale_payload((product, 1)))
    assert response.status_code == 400
    assert response.json()["code"] == "PRODUCT_INACTIVE"


def test_unknown_product_returns_404(client, factory, seller):
    payload = {"items": [{"product_id": 999999, "quantity": 1}], "payment": {"method": "CARD"}}
    assert client.post("/api/v1/sales", headers=factory.headers(seller), json=payload).status_code == 404


@pytest.mark.parametrize(
    "items",
    [
        [],
        [{"product_id": 1, "quantity": 0}],
        [{"product_id": 1, "quantity": 1}, {"product_id": 1, "quantity": 2}],
    ],
    ids=["sans-ligne", "quantite-nulle", "produit-en-double"],
)
def test_invalid_sale_lines_are_rejected(client, factory, seller, items):
    payload = {"items": items, "payment": {"method": "CARD"}}
    assert client.post("/api/v1/sales", headers=factory.headers(seller), json=payload).status_code == 422


def test_sales_list_is_scoped_to_user_store(client, factory):
    shop = factory.store()
    product = factory.product(stock=10)
    factory.add_stock(product, 10, shop)
    client.post("/api/v1/sales", headers=factory.headers(factory.admin()), json=sale_payload((product, 1)))
    shop_seller = factory.user(RoleName.VENDEUR, shop)
    shop_headers = factory.headers(shop_seller)
    own_sale = client.post("/api/v1/sales", headers=shop_headers, json=sale_payload((product, 1))).json()

    listing = client.get("/api/v1/sales", headers=shop_headers).json()
    admin_listing = client.get("/api/v1/sales", headers=factory.headers(factory.admin())).json()

    assert [s["id"] for s in listing["items"]] == [own_sale["id"]]
    assert admin_listing["total"] == 2


def test_sale_of_another_store_is_forbidden(client, factory):
    product = factory.product(stock=10)
    sale_id = client.post(
        "/api/v1/sales", headers=factory.headers(factory.admin()), json=sale_payload((product, 1))
    ).json()["id"]
    other_seller = factory.user(RoleName.VENDEUR, factory.store())
    assert client.get(f"/api/v1/sales/{sale_id}", headers=factory.headers(other_seller)).status_code == 403


def test_search_sales_by_customer_name(client, factory, seller):
    product = factory.product(stock=10)
    headers = factory.headers(seller)
    client.post("/api/v1/sales", headers=headers, json=sale_payload((product, 1), customer_name="Rasoa"))
    client.post("/api/v1/sales", headers=headers, json=sale_payload((product, 1), customer_name="Rabe"))

    response = client.get("/api/v1/sales", headers=headers, params={"search": "RASOA"})

    assert [s["customer_name"] for s in response.json()["items"]] == ["rasoa"]
