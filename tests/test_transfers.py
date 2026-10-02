from sqlalchemy import func, select

from app.core.permissions import RoleName
from app.models import AuditLog, StockMovement, StockTransfer


def transfer(client, headers, product, quantity, destination, **fields):
    return client.post(
        "/api/v1/stock/transfers",
        headers=headers,
        json={
            "product_id": product.id,
            "quantity": quantity,
            "destination_store_id": destination.id,
            **fields,
        },
    )


def test_partial_transfer_creates_article_in_destination(client, factory, db):
    """10 articles au STOCK LOCAL, 5 transférés : 5 restent, 5 arrivent dans le magasin."""
    local = factory.default_store()
    shop = factory.store("Magasin Analakely")
    product = factory.product(name="Article 1", stock=10)

    response = transfer(client, factory.headers(factory.admin()), product, 5, shop, reason="Réassort")

    assert response.status_code == 201
    body = response.json()
    assert body["transfer"]["source_store"]["name"] == "stock local"
    assert body["transfer"]["destination_store"]["name"] == "magasin analakely"
    assert body["transfer"]["reference"].startswith("trf-")
    assert body["source_stock"]["quantity"] == 5 and body["source_stock"]["status"] != "RUPTURE"
    assert body["destination_stock"]["quantity"] == 5
    assert body["destination_stock"]["product"]["name"] == "article 1"
    assert factory.store_quantity(local, product) == 5
    assert factory.store_quantity(shop, product) == 5
    db.refresh(product)
    assert product.stock == 10  # le total ne change pas : le stock est déplacé


def test_full_transfer_moves_everything_and_source_becomes_out_of_stock(client, factory):
    local = factory.default_store()
    shop = factory.store()
    product = factory.product(stock=10)
    headers = factory.headers(factory.admin())

    response = transfer(client, headers, product, 10, shop)

    assert response.status_code == 201
    assert response.json()["source_stock"]["quantity"] == 0
    assert response.json()["source_stock"]["status"] == "RUPTURE"
    assert response.json()["destination_stock"]["quantity"] == 10
    local_stock = client.get(
        f"/api/v1/stores/{local.id}/stock", headers=headers, params={"status": "RUPTURE"}
    )
    assert [line["product"]["id"] for line in local_stock.json()["items"]] == [product.id]


def test_transfer_to_store_that_already_has_the_article_adds_quantity(client, factory):
    shop = factory.store()
    product = factory.product(stock=10)
    factory.add_stock(product, 3, shop)

    response = transfer(client, factory.headers(factory.admin()), product, 4, shop)

    assert response.json()["destination_stock"]["quantity"] == 7
    assert response.json()["source_stock"]["quantity"] == 6


def test_transfer_creates_two_movements_and_an_audit_entry(client, factory, db):
    shop = factory.store()
    product = factory.product(stock=10)

    body = transfer(client, factory.headers(factory.admin()), product, 4, shop).json()

    transfer_id = body["transfer"]["id"]
    moves = db.scalars(select(StockMovement).where(StockMovement.reference == f"TRF-{transfer_id:06d}")).all()
    assert sorted((m.type.value, m.quantity, m.store_id) for m in moves) == [
        ("TRANSFER_IN", 4, shop.id),
        ("TRANSFER_OUT", -4, factory.default_store().id),
    ]
    assert db.scalar(
        select(AuditLog).where(AuditLog.action == "stock.transfer", AuditLog.entity_id == transfer_id)
    )


def test_transfer_with_insufficient_stock_changes_nothing(client, factory, db):
    shop = factory.store()
    product = factory.product(stock=3)

    response = transfer(client, factory.headers(factory.admin()), product, 5, shop)

    assert response.status_code == 400
    assert response.json()["code"] == "INSUFFICIENT_STOCK"
    assert db.scalar(select(func.count()).select_from(StockTransfer)) == 0
    assert db.scalar(select(func.count()).select_from(StockMovement)) == 0
    assert factory.store_quantity(factory.default_store(), product) == 3
    assert factory.store_quantity(shop, product) == 0


def test_transfer_to_same_store_is_refused(client, factory):
    product = factory.product(stock=3)
    response = transfer(client, factory.headers(factory.admin()), product, 1, factory.default_store())
    assert response.status_code == 400


def test_transfer_to_inactive_store_is_refused(client, factory):
    product = factory.product(stock=3)
    closed = factory.store(is_active=False)
    response = transfer(client, factory.headers(factory.admin()), product, 1, closed)
    assert response.status_code == 400
    assert response.json()["code"] == "STORE_INACTIVE"


def test_store_bound_user_transfers_from_his_own_store(client, factory):
    shop_a, shop_b = factory.store(), factory.store()
    product = factory.product(stock=5, store=shop_a)
    magasinier = factory.user(RoleName.MAGASINIER, shop_a)
    headers = factory.headers(magasinier)

    ok = transfer(client, headers, product, 2, shop_b)
    forbidden = transfer(client, headers, product, 1, shop_b, source_store_id=factory.default_store().id)

    assert ok.status_code == 201
    assert ok.json()["transfer"]["source_store"]["id"] == shop_a.id
    assert forbidden.status_code == 403


def test_vendeur_cannot_transfer(client, factory):
    product = factory.product(stock=5)
    response = transfer(client, factory.headers(factory.user(RoleName.VENDEUR)), product, 1, factory.store())
    assert response.status_code == 403


def test_list_and_get_transfers(client, factory):
    shop = factory.store()
    product = factory.product(stock=10)
    headers = factory.headers(factory.admin())
    transfer_id = transfer(client, headers, product, 2, shop).json()["transfer"]["id"]
    transfer(client, headers, product, 1, factory.store())

    listing = client.get("/api/v1/stock/transfers", headers=headers, params={"destination_store_id": shop.id})
    detail = client.get(f"/api/v1/stock/transfers/{transfer_id}", headers=headers)

    assert listing.json()["total"] == 1
    assert detail.json()["quantity"] == 2


def test_transferred_stock_can_be_sold_in_destination_store(client, factory):
    shop = factory.store()
    product = factory.product(stock=10)
    transfer(client, factory.headers(factory.admin()), product, 4, shop)
    vendeur = factory.user(RoleName.VENDEUR, shop)

    sale = client.post(
        "/api/v1/sales",
        headers=factory.headers(vendeur),
        json={"items": [{"product_id": product.id, "quantity": 4}], "payment": {"method": "CARD"}},
    )

    assert sale.status_code == 201
    assert factory.store_quantity(shop, product) == 0
    assert factory.store_quantity(factory.default_store(), product) == 6


def test_store_user_sees_transfers_sent_or_received_by_his_store(client, factory):
    shop, other_shop = factory.store(), factory.store()
    product = factory.product(stock=10)
    admin_headers = factory.headers(factory.admin())
    received = transfer(client, admin_headers, product, 2, shop).json()["transfer"]["id"]
    other = transfer(client, admin_headers, product, 1, other_shop).json()["transfer"]["id"]
    shop_headers = factory.headers(factory.user(RoleName.MAGASINIER, shop))

    listing = client.get("/api/v1/stock/transfers", headers=shop_headers).json()

    assert [t["id"] for t in listing["items"]] == [received]
    assert client.get(f"/api/v1/stock/transfers/{other}", headers=shop_headers).status_code == 403
