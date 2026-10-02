from sqlalchemy import func, select

from app.core.permissions import RoleName
from app.models import Product, StockMovement, StoreStock
from app.models.enums import StockMovementType


def movements(db, product):
    return list(db.scalars(select(StockMovement).where(StockMovement.product_id == product.id)))


def total_of_store_lines(db, product):
    return db.scalar(select(func.sum(StoreStock.quantity)).where(StoreStock.product_id == product.id))


def test_entry_goes_to_default_store_for_unattached_user(client, factory, db):
    product = factory.product()

    response = client.post(
        "/api/v1/stock/entry",
        headers=factory.headers(factory.admin()),
        json={"product_id": product.id, "quantity": 10, "reference": "bl-2026-001", "reason": "Livraison"},
    )

    assert response.status_code == 201
    body = response.json()
    assert body["type"] == "ENTRY" and body["quantity"] == 10
    assert body["store"]["name"] == "stock local"
    assert body["reference"] == "bl-2026-001"
    db.refresh(product)
    assert product.stock == 10
    assert factory.store_quantity(factory.default_store(), product) == 10


def test_entry_by_store_user_goes_to_his_store(client, factory):
    store = factory.store()
    magasinier = factory.user(RoleName.MAGASINIER, store)
    product = factory.product()

    response = client.post(
        "/api/v1/stock/entry",
        headers=factory.headers(magasinier),
        json={"product_id": product.id, "quantity": 4},
    )

    assert response.status_code == 201
    assert factory.store_quantity(store, product) == 4
    assert factory.store_quantity(factory.default_store(), product) == 0


def test_store_user_cannot_move_stock_of_another_store(client, factory):
    magasinier = factory.user(RoleName.MAGASINIER, factory.store())
    product = factory.product()
    response = client.post(
        "/api/v1/stock/entry",
        headers=factory.headers(magasinier),
        json={"product_id": product.id, "quantity": 4, "store_id": factory.default_store().id},
    )
    assert response.status_code == 403


def test_exit_with_insufficient_stock_is_refused(client, factory, db):
    product = factory.product(stock=3)

    response = client.post(
        "/api/v1/stock/exit",
        headers=factory.headers(factory.admin()),
        json={"product_id": product.id, "quantity": 5},
    )

    assert response.status_code == 400
    assert response.json()["code"] == "INSUFFICIENT_STOCK"
    assert "disponible 3, demandé 5" in response.json()["detail"]
    db.refresh(product)
    assert product.stock == 3
    assert movements(db, product) == []


def test_loss_creates_negative_movement(client, factory, db):
    product = factory.product(stock=10)

    response = client.post(
        "/api/v1/stock/exit",
        headers=factory.headers(factory.admin()),
        json={"product_id": product.id, "quantity": 2, "type": "LOSS", "reason": "Casse"},
    )

    assert response.status_code == 201
    assert response.json()["type"] == "LOSS" and response.json()["quantity"] == -2
    db.refresh(product)
    assert product.stock == 8


def test_adjustment_sets_counted_quantity(client, factory, db):
    product = factory.product(stock=10)
    headers = factory.headers(factory.admin())

    response = client.post(
        "/api/v1/stock/adjust",
        headers=headers,
        json={"product_id": product.id, "new_quantity": 7, "reason": "Inventaire mensuel"},
    )
    unchanged = client.post(
        "/api/v1/stock/adjust",
        headers=headers,
        json={"product_id": product.id, "new_quantity": 7, "reason": "Inventaire mensuel"},
    )

    assert response.status_code == 201
    assert response.json()["type"] == "ADJUSTMENT" and response.json()["quantity"] == -3
    assert unchanged.status_code == 400
    db.refresh(product)
    assert product.stock == 7


def test_adjustment_requires_reason(client, factory):
    product = factory.product(stock=10)
    response = client.post(
        "/api/v1/stock/adjust",
        headers=factory.headers(factory.admin()),
        json={"product_id": product.id, "new_quantity": 7},
    )
    assert response.status_code == 422


def test_unknown_product_returns_404(client, factory):
    response = client.post(
        "/api/v1/stock/entry",
        headers=factory.headers(factory.admin()),
        json={"product_id": 999999, "quantity": 1},
    )
    assert response.status_code == 404


def test_product_total_equals_sum_of_store_lines(client, factory, db):
    store = factory.store()
    product = factory.product()
    headers = factory.headers(factory.admin())
    client.post("/api/v1/stock/entry", headers=headers, json={"product_id": product.id, "quantity": 20})
    client.post(
        "/api/v1/stock/entry",
        headers=headers,
        json={"product_id": product.id, "quantity": 5, "store_id": store.id},
    )
    client.post("/api/v1/stock/exit", headers=headers, json={"product_id": product.id, "quantity": 3})

    db.refresh(product)
    assert product.stock == 22 == total_of_store_lines(db, product)
    assert sum(m.quantity for m in movements(db, product)) == 22


def test_movement_history_filters_and_store_scope(client, factory):
    store = factory.store()
    product = factory.product()
    admin_headers = factory.headers(factory.admin())
    client.post("/api/v1/stock/entry", headers=admin_headers, json={"product_id": product.id, "quantity": 5})
    client.post(
        "/api/v1/stock/entry",
        headers=admin_headers,
        json={"product_id": product.id, "quantity": 2, "store_id": store.id},
    )
    vendeur_headers = factory.headers(factory.user(RoleName.VENDEUR, store))

    all_movements = client.get(
        "/api/v1/stock/movements", headers=admin_headers, params={"product_id": product.id}
    ).json()
    own_store = client.get(
        "/api/v1/stock/movements", headers=vendeur_headers, params={"product_id": product.id}
    ).json()

    assert all_movements["total"] == 2
    assert [m["quantity"] for m in own_store["items"]] == [2]


def test_inactive_product_stock_line_is_kept_but_product_marked_inactive(client, factory, db):
    product = factory.product(stock=5, is_active=False)
    response = client.get(
        f"/api/v1/stores/{factory.default_store().id}/stock", headers=factory.headers(factory.admin())
    )
    line = next(item for item in response.json()["items"] if item["product"]["id"] == product.id)
    assert line["product"]["is_active"] is False
    assert db.get(Product, product.id).stock == 5


def test_movement_types_are_listed_by_type(client, factory):
    product = factory.product(stock=10)
    headers = factory.headers(factory.admin())
    client.post(
        "/api/v1/stock/exit", headers=headers, json={"product_id": product.id, "quantity": 1, "type": "LOSS"}
    )
    response = client.get("/api/v1/stock/movements", headers=headers, params={"type": StockMovementType.LOSS})
    assert [m["type"] for m in response.json()["items"]] == ["LOSS"]
