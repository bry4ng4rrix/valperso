from app.core.config import settings
from app.core.permissions import RoleName
from app.models import Store


def test_admin_can_create_several_stores(client, factory, db):
    headers = factory.headers(factory.admin())

    first = client.post(
        "/api/v1/stores", headers=headers, json={"name": "Magasin Analakely", "address": "Rue 1"}
    )
    second = client.post("/api/v1/stores", headers=headers, json={"name": "Magasin Ivandry"})

    assert first.status_code == 201 and second.status_code == 201
    assert first.json()["name"] == "magasin analakely"
    assert first.json()["is_default"] is False
    assert db.get(Store, first.json()["id"]).name == "MAGASIN ANALAKELY"


def test_store_name_must_be_unique_case_insensitive(client, factory):
    factory.store("Magasin Tana")
    response = client.post(
        "/api/v1/stores", headers=factory.headers(factory.admin()), json={"name": "magasin tana"}
    )
    assert response.status_code == 409


def test_default_store_is_listed_first(client, factory):
    factory.store("Aaa Premier Alphabétique")

    response = client.get("/api/v1/stores", headers=factory.headers(factory.admin()))

    items = response.json()["items"]
    assert items[0]["name"] == "stock local"
    assert items[0]["is_default"] is True


def test_default_store_cannot_be_deleted_or_deactivated(client, factory):
    headers = factory.headers(factory.admin())
    default_id = factory.default_store().id

    assert client.delete(f"/api/v1/stores/{default_id}", headers=headers).status_code == 400
    response = client.patch(f"/api/v1/stores/{default_id}", headers=headers, json={"is_active": False})
    assert response.status_code == 400


def test_delete_store_deactivates_it(client, factory, db):
    store = factory.store()
    response = client.delete(f"/api/v1/stores/{store.id}", headers=factory.headers(factory.admin()))
    assert response.status_code == 204
    db.refresh(store)
    assert store.is_active is False


def test_store_stock_lists_articles_with_status(client, factory):
    store = factory.store()
    factory.product(name="Riz", stock=50, store=store)
    factory.product(name="Huile", stock=settings.LOW_STOCK_THRESHOLD, store=store)
    sold_out = factory.product(name="Sucre", stock=1, store=store)
    factory.add_stock(sold_out, -1, store)
    factory.product(name="Sel", stock=10)  # dans le STOCK LOCAL uniquement

    response = client.get(f"/api/v1/stores/{store.id}/stock", headers=factory.headers(factory.admin()))

    assert response.status_code == 200
    statuses = {line["product"]["name"]: line["status"] for line in response.json()["items"]}
    assert statuses == {"riz": "EN_STOCK", "huile": "STOCK_FAIBLE", "sucre": "RUPTURE"}


def test_store_stock_can_be_filtered_and_searched(client, factory):
    store = factory.store()
    factory.product(name="Riz rouge", stock=50, store=store)
    factory.product(name="Riz blanc", stock=1, store=store)
    factory.product(name="Huile", stock=50, store=store)
    headers = factory.headers(factory.admin())
    url = f"/api/v1/stores/{store.id}/stock"

    by_search = client.get(url, headers=headers, params={"search": "RIZ"}).json()
    by_status = client.get(url, headers=headers, params={"status": "STOCK_FAIBLE"}).json()

    assert by_search["total"] == 2
    assert [line["product"]["name"] for line in by_status["items"]] == ["riz blanc"]


def test_store_bound_user_sees_only_his_store_stock(client, factory):
    store = factory.store()
    vendeur = factory.user(RoleName.VENDEUR, store)
    response = client.get(
        f"/api/v1/stores/{factory.default_store().id}/stock", headers=factory.headers(vendeur)
    )
    assert response.status_code == 403
