from app.models import Store


def test_create_store_without_any_vendeur(client, admin_headers, db):
    response = client.post(
        "/api/v1/stores",
        headers=admin_headers,
        json={"name": "Magasin 1", "address": "Analakely", "phone": "0201234567"},
    )

    assert response.status_code == 201
    body = response.json()
    assert body["name"] == "magasin 1" and body["is_central"] is False and body["is_active"] is True
    assert db.get(Store, body["id"]).name == "MAGASIN 1"
    employees = client.get(f"/api/v1/stores/{body['id']}/employees", headers=admin_headers).json()
    assert employees["total"] == 0


def test_several_stores_with_stock_local_first(client, admin_headers):
    for name in ("Magasin 2", "Magasin 1", "Aaa Magasin"):
        client.post("/api/v1/stores", headers=admin_headers, json={"name": name})

    names = [store["name"] for store in client.get("/api/v1/stores", headers=admin_headers).json()["items"]]

    assert names == ["stock local", "aaa magasin", "magasin 1", "magasin 2"]


def test_store_name_is_unique_case_insensitive(client, factory, admin_headers):
    factory.store("Magasin Tana")
    assert (
        client.post("/api/v1/stores", headers=admin_headers, json={"name": "magasin tana"}).status_code == 409
    )


def test_update_store(client, factory, admin_headers):
    store = factory.store()
    response = client.patch(f"/api/v1/stores/{store.id}", headers=admin_headers, json={"address": "Ivandry"})
    assert response.status_code == 200 and response.json()["address"] == "ivandry"


def test_deactivate_store(client, factory, admin_headers, db):
    store = factory.store()
    assert client.delete(f"/api/v1/stores/{store.id}", headers=admin_headers).status_code == 204
    db.refresh(store)
    assert store.is_active is False


def test_stock_local_exists_and_is_protected(client, factory, admin_headers):
    central = factory.central_store()
    assert central.name == "STOCK LOCAL" and central.is_central

    assert client.delete(f"/api/v1/stores/{central.id}", headers=admin_headers).status_code == 400
    response = client.patch(f"/api/v1/stores/{central.id}", headers=admin_headers, json={"is_active": False})
    assert response.status_code == 400


def test_operations_in_inactive_store_are_refused(client, factory, admin_headers):
    store = factory.store(is_active=False)
    product = factory.product()
    response = client.post(
        "/api/v1/stock/entry",
        headers=admin_headers,
        json={"product_id": product.id, "quantity": 1, "store_id": store.id},
    )
    assert response.status_code == 400 and response.json()["code"] == "INACTIVE_STORE"
