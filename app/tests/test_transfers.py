import pytest
from sqlalchemy import func, select

from app.core.permissions import PermissionCode, RoleName
from app.models import AuditLog, Stock, StockMovement, StockTransfer
from app.services import audit_service


def transfer(client, headers, destination, *lines, **fields):
    return client.post(
        "/api/v1/stock-transfers",
        headers=headers,
        json={
            "destination_store_id": destination.id,
            "items": [{"product_id": product.id, "quantity": quantity} for product, quantity in lines],
            **fields,
        },
    )


def global_stock(db, product) -> int:
    db.expire_all()
    return db.scalar(select(func.sum(Stock.quantity)).where(Stock.product_id == product.id))


@pytest.fixture
def shop(factory):
    return factory.store("Magasin 1")


@pytest.fixture
def product(factory):
    return factory.product(name="Article 1", stock=10)  # 10 au Stock Local


def test_transfer_5_of_10(client, factory, admin_headers, shop, product, db):
    response = transfer(client, admin_headers, shop, (product, 5))

    assert response.status_code == 201
    body = response.json()
    assert body["reference"].startswith("TRF-") and body["status"] == "COMPLETED" and body["completed_at"]
    assert body["source_store"]["name"] == "stock local" and body["destination_store"]["name"] == "magasin 1"
    assert body["stock_levels"] == [
        {"product": {"id": product.id, "reference": product.reference.lower(), "name": "article 1"},
         "source_quantity": 5, "destination_quantity": 5}
    ]  # fmt: skip
    assert factory.quantity(factory.central_store(), product) == 5
    assert factory.quantity(shop, product) == 5
    assert global_stock(db, product) == 10


def test_transfer_10_of_10_moves_everything(client, factory, admin_headers, shop, product, db):
    response = transfer(client, admin_headers, shop, (product, 10))

    assert response.json()["stock_levels"][0]["source_quantity"] == 0
    assert response.json()["stock_levels"][0]["destination_quantity"] == 10
    assert global_stock(db, product) == 10  # stock déplacé, pas perdu
    out = client.get(
        "/api/v1/stock/out-of-stock", headers=admin_headers, params={"store_id": factory.central_store().id}
    )
    assert [line["product"]["id"] for line in out.json()["items"]] == [product.id]


def test_transfer_11_of_10_is_refused_and_changes_nothing(client, factory, admin_headers, shop, product, db):
    response = transfer(client, admin_headers, shop, (product, 11))

    assert response.status_code == 400
    assert response.json()["code"] == "INSUFFICIENT_STOCK"
    assert factory.quantity(factory.central_store(), product) == 10
    assert factory.quantity(shop, product) == 0
    assert db.scalar(select(func.count()).select_from(StockTransfer)) == 0
    assert db.scalar(select(func.count()).select_from(StockMovement)) == 0


def test_destination_without_stock_line_gets_one(client, factory, admin_headers, shop, product, db):
    assert db.scalar(select(Stock).where(Stock.store_id == shop.id)) is None
    transfer(client, admin_headers, shop, (product, 3))
    lines = db.scalars(select(Stock).where(Stock.store_id == shop.id, Stock.product_id == product.id)).all()
    assert [line.quantity for line in lines] == [3]


def test_destination_with_existing_stock_is_increased_without_duplicate_line(
    client, factory, admin_headers, shop, product, db
):
    factory.add_stock(product, 2, shop)

    transfer(client, admin_headers, shop, (product, 4))

    lines = db.scalars(select(Stock).where(Stock.store_id == shop.id, Stock.product_id == product.id)).all()
    assert [line.quantity for line in lines] == [6]


def test_source_equal_destination_is_refused(client, factory, admin_headers, product):
    central = factory.central_store()
    explicit = transfer(client, admin_headers, central, (product, 1), source_store_id=central.id)
    implicit = transfer(client, admin_headers, central, (product, 1))  # source par défaut = Stock Local
    assert explicit.status_code == 422
    assert implicit.status_code == 400 and implicit.json()["code"] == "INVALID_TRANSFER"


def test_quantity_must_be_positive(client, admin_headers, shop, product):
    assert transfer(client, admin_headers, shop, (product, 0)).status_code == 422


def test_transfer_creates_movements_and_audit(client, factory, admin_headers, shop, product, db):
    body = transfer(client, admin_headers, shop, (product, 4)).json()

    moves = db.scalars(select(StockMovement).where(StockMovement.reference == body["reference"])).all()
    assert sorted((m.type.value, m.quantity, m.store_id) for m in moves) == [
        ("TRANSFER_IN", 4, shop.id),
        ("TRANSFER_OUT", -4, factory.central_store().id),
    ]
    assert db.scalar(
        select(AuditLog).where(AuditLog.action == "stock_transfer.create", AuditLog.entity_id == body["id"])
    )


def test_transfer_with_several_products_is_all_or_nothing(client, factory, admin_headers, shop, product, db):
    other = factory.product(stock=2)

    response = transfer(client, admin_headers, shop, (product, 5), (other, 3))

    assert response.status_code == 400
    assert factory.quantity(factory.central_store(), product) == 10  # le premier produit n'a pas bougé
    assert factory.quantity(shop, product) == 0


def test_rollback_when_an_unexpected_error_occurs(
    client, factory, admin_headers, shop, product, db, monkeypatch
):
    def broken_audit(*args, **kwargs):
        raise RuntimeError("panne simulée")

    monkeypatch.setattr(audit_service, "record", broken_audit)
    with pytest.raises(RuntimeError):
        transfer(client, admin_headers, shop, (product, 5))

    assert factory.quantity(factory.central_store(), product) == 10
    assert factory.quantity(shop, product) == 0
    assert db.scalar(select(func.count()).select_from(StockMovement)) == 0


def test_inactive_product_or_store_cannot_be_transferred(client, factory, admin_headers, shop):
    inactive = factory.product(stock=5, is_active=False)
    product = factory.product(stock=5)
    assert transfer(client, admin_headers, shop, (inactive, 1)).json()["code"] == "INACTIVE_PRODUCT"
    assert (
        transfer(client, admin_headers, factory.store(is_active=False), (product, 1)).json()["code"]
        == "INACTIVE_STORE"
    )


def test_cancel_transfer_moves_stock_back(client, factory, admin_headers, shop, product, db):
    transfer_id = transfer(client, admin_headers, shop, (product, 4)).json()["id"]

    response = client.post(f"/api/v1/stock-transfers/{transfer_id}/cancel", headers=admin_headers)
    again = client.post(f"/api/v1/stock-transfers/{transfer_id}/cancel", headers=admin_headers)

    assert response.status_code == 200 and response.json()["status"] == "CANCELLED"
    assert factory.quantity(factory.central_store(), product) == 10
    assert factory.quantity(shop, product) == 0
    assert again.status_code == 400


def test_cancel_is_refused_when_destination_no_longer_has_the_stock(
    client, factory, admin_headers, shop, product
):
    transfer_id = transfer(client, admin_headers, shop, (product, 4)).json()["id"]
    client.post(
        "/api/v1/stock/exit",
        headers=admin_headers,
        json={"product_id": product.id, "quantity": 2, "store_id": shop.id},
    )

    response = client.post(f"/api/v1/stock-transfers/{transfer_id}/cancel", headers=admin_headers)

    assert response.status_code == 400 and response.json()["code"] == "INSUFFICIENT_STOCK"


def test_list_and_get_transfers(client, factory, admin_headers, shop, product):
    transfer_id = transfer(client, admin_headers, shop, (product, 2)).json()["id"]
    transfer(client, admin_headers, factory.store(), (product, 1))

    listing = client.get(
        "/api/v1/stock-transfers", headers=admin_headers, params={"destination_store_id": shop.id}
    )
    detail = client.get(f"/api/v1/stock-transfers/{transfer_id}", headers=admin_headers)

    assert listing.json()["total"] == 1
    assert detail.json()["items"][0]["quantity"] == 2


def test_vendeur_can_only_transfer_from_his_store_and_see_his_transfers(
    client, factory, admin_headers, shop, product
):
    other_shop = factory.store()
    factory.add_stock(product, 5, shop)
    factory.grant(RoleName.VENDEUR, PermissionCode.STORE_TRANSFER_CREATE, PermissionCode.STORE_TRANSFER_VIEW)
    headers = factory.headers(factory.vendeur(shop))

    own = transfer(client, headers, other_shop, (product, 2))
    forbidden = transfer(
        client, headers, other_shop, (product, 1), source_store_id=factory.central_store().id
    )
    unrelated = transfer(client, admin_headers, other_shop, (product, 1)).json()["id"]

    assert own.status_code == 201 and own.json()["source_store"]["id"] == shop.id
    assert forbidden.status_code == 403
    assert [t["id"] for t in client.get("/api/v1/stock-transfers", headers=headers).json()["items"]] == [
        own.json()["id"]
    ]
    assert client.get(f"/api/v1/stock-transfers/{unrelated}", headers=headers).status_code == 403


def test_stock_transfer_permission_is_an_accepted_alternative(client, factory, shop):
    factory.set_role_permissions(RoleName.VENDEUR, PermissionCode.STOCK_TRANSFER)
    product = factory.product()
    factory.add_stock(product, 3, shop)
    headers = factory.headers(factory.vendeur(shop))
    assert transfer(client, headers, factory.central_store(), (product, 1)).status_code == 201


def test_vendeur_cannot_transfer_by_default(client, factory, shop, product):
    headers = factory.headers(factory.vendeur(shop))
    assert transfer(client, headers, factory.store(), (product, 1)).status_code == 403
