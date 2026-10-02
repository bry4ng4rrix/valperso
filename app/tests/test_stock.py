from sqlalchemy import select

from app.core.permissions import PermissionCode, RoleName
from app.models import StockMovement


def movements(db, product):
    return db.scalars(select(StockMovement).where(StockMovement.product_id == product.id)).all()


def entry(client, headers, product, quantity, **fields):
    return client.post("/api/v1/stock/entry", headers=headers, json={"product_id": product.id, "quantity": quantity, **fields})


def test_admin_entry_goes_to_stock_local_by_default(client, factory, admin, admin_headers, db):
    product = factory.product()

    response = entry(client, admin_headers, product, 10, reference="bl-2026-001", reason="Livraison")

    assert response.status_code == 201
    body = response.json()
    assert body["type"] == "ENTRY" and body["quantity"] == 10
    assert body["store"]["name"] == "stock local" and body["user"]["id"] == admin.id
    assert factory.quantity(factory.central_store(), product) == 10


def test_entry_creates_the_stock_line_of_a_new_store(client, factory, admin_headers):
    store = factory.store()
    product = factory.product()

    entry(client, admin_headers, product, 4, store_id=store.id)

    assert factory.quantity(store, product) == 4


def test_exit_and_loss(client, factory, admin_headers, db):
    product = factory.product(stock=10)

    exit_ = client.post("/api/v1/stock/exit", headers=admin_headers, json={"product_id": product.id, "quantity": 3})
    loss = client.post(
        "/api/v1/stock/exit",
        headers=admin_headers,
        json={"product_id": product.id, "quantity": 2, "type": "LOSS", "reason": "Casse"},
    )

    assert (exit_.json()["type"], exit_.json()["quantity"]) == ("EXIT", -3)
    assert (loss.json()["type"], loss.json()["quantity"]) == ("LOSS", -2)
    assert factory.quantity(factory.central_store(), product) == 5


def test_exit_beyond_stock_is_refused_and_stock_never_negative(client, factory, admin_headers, db):
    product = factory.product(stock=3)

    response = client.post("/api/v1/stock/exit", headers=admin_headers, json={"product_id": product.id, "quantity": 5})

    assert response.status_code == 400
    assert response.json()["code"] == "INSUFFICIENT_STOCK"
    assert "disponible 3, demandé 5" in response.json()["detail"]
    assert factory.quantity(factory.central_store(), product) == 3
    assert movements(db, product) == []


def test_adjustment_sets_counted_quantity(client, factory, admin_headers):
    product = factory.product(stock=10)
    body = {"product_id": product.id, "new_quantity": 7, "reason": "Inventaire mensuel"}

    adjusted = client.post("/api/v1/stock/adjust", headers=admin_headers, json=body)
    unchanged = client.post("/api/v1/stock/adjust", headers=admin_headers, json=body)

    assert (adjusted.json()["type"], adjusted.json()["quantity"]) == ("ADJUSTMENT", -3)
    assert unchanged.status_code == 400
    assert factory.quantity(factory.central_store(), product) == 7


def test_alert_threshold_low_stock_and_out_of_stock(client, factory, admin_headers):
    product = factory.product(stock=3)
    line = factory.add_stock(product, 0)
    url = f"/api/v1/stock/{line.id}"

    assert client.get(url, headers=admin_headers).json()["low_stock"] is True  # 3 <= 5 (seuil par défaut)
    updated = client.put(f"{url}/alert-threshold", headers=admin_headers, json={"alert_threshold": 2})
    assert (updated.json()["alert_threshold"], updated.json()["low_stock"]) == (2, False)

    client.post("/api/v1/stock/exit", headers=admin_headers, json={"product_id": product.id, "quantity": 3})
    empty = client.get(url, headers=admin_headers).json()
    assert (empty["quantity"], empty["out_of_stock"], empty["low_stock"]) == (0, True, False)


def test_low_stock_and_out_of_stock_endpoints(client, factory, admin_headers):
    low = factory.product(name="Huile", stock=2)
    factory.product(name="Riz", stock=50)
    empty = factory.product(name="Sucre")  # 0 au Stock Local

    low_items = client.get("/api/v1/stock/low-stock", headers=admin_headers).json()["items"]
    out_items = client.get("/api/v1/stock/out-of-stock", headers=admin_headers).json()["items"]

    assert [line["product"]["id"] for line in low_items] == [low.id]
    assert [line["product"]["id"] for line in out_items] == [empty.id]


def test_stock_list_filters(client, factory, admin_headers):
    store = factory.store()
    product = factory.product(name="Savon", stock=10)
    factory.add_stock(product, 1, store)
    url = "/api/v1/stock"

    by_product = client.get(url, headers=admin_headers, params={"product_id": product.id}).json()
    by_store = client.get(url, headers=admin_headers, params={"store_id": store.id}).json()
    low = client.get(url, headers=admin_headers, params={"product_id": product.id, "low_stock": True}).json()
    searched = client.get(url, headers=admin_headers, params={"search": "savon"}).json()

    assert by_product["total"] == 2 and by_store["total"] == 1
    assert [line["store"]["id"] for line in low["items"]] == [store.id]
    assert searched["total"] == 2


def test_store_stock_endpoint(client, factory, admin_headers):
    store = factory.store()
    factory.add_stock(factory.product(), 5, store)
    response = client.get(f"/api/v1/stock/store/{store.id}", headers=admin_headers)
    assert response.json()["total"] == 1 and response.json()["items"][0]["quantity"] == 5


def test_movement_history(client, factory, admin_headers):
    product = factory.product()
    entry(client, admin_headers, product, 5)
    client.post("/api/v1/stock/exit", headers=admin_headers, json={"product_id": product.id, "quantity": 1})

    response = client.get("/api/v1/stock/movements", headers=admin_headers, params={"product_id": product.id})

    assert [(m["type"], m["quantity"]) for m in response.json()["items"]] == [("EXIT", -1), ("ENTRY", 5)]


def test_vendeur_entry_goes_to_his_store_when_allowed(client, factory):
    store = factory.store()
    factory.grant(RoleName.VENDEUR, PermissionCode.STOCK_ENTRY)
    product = factory.product()
    headers = factory.headers(factory.vendeur(store))

    assert entry(client, headers, product, 3).status_code == 201
    assert factory.quantity(store, product) == 3
    assert entry(client, headers, product, 3, store_id=factory.central_store().id).status_code == 403


def test_vendeur_cannot_move_stock_by_default(client, factory):
    product = factory.product(stock=5)
    headers = factory.headers(factory.vendeur(factory.store()))
    assert entry(client, headers, product, 1).status_code == 403
