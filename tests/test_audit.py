from app.core.permissions import RoleName


def test_product_lifecycle_is_audited(client, factory):
    admin = factory.admin()
    headers = factory.headers(admin)
    product_id = client.post(
        "/api/v1/products",
        headers=headers,
        json={"reference": "aud-1", "name": "Produit audité", "purchase_price": 1, "selling_price": 2},
    ).json()["id"]
    client.patch(f"/api/v1/products/{product_id}", headers=headers, json={"name": "Nouveau nom"})
    client.delete(f"/api/v1/products/{product_id}", headers=headers)

    response = client.get(
        "/api/v1/audit",
        headers=headers,
        params={"entity_type": "product", "entity_id": product_id, "sort": "created_at"},
    )

    logs = response.json()["items"]
    assert [log["action"] for log in logs] == ["product.create", "product.update", "product.delete"]
    assert all(log["user_id"] == admin.id and log["ip_address"] == "testclient" for log in logs)
    # Les données d'audit sont enregistrées telles qu'en base (majuscules).
    assert logs[0]["new_data"]["name"] == "PRODUIT AUDITÉ"
    assert logs[1]["old_data"]["name"] == "PRODUIT AUDITÉ" and logs[1]["new_data"]["name"] == "NOUVEAU NOM"
    assert logs[2]["old_data"]["is_active"] is True


def test_sensitive_operations_are_audited(client, factory):
    caissier = factory.user(RoleName.CAISSIER)
    headers = factory.headers(caissier)
    product = factory.product(stock=5)
    register_id = client.post(
        "/api/v1/cash/registers/open", headers=headers, json={"opening_amount": 0}
    ).json()["id"]
    client.post(
        "/api/v1/sales",
        headers=headers,
        json={"items": [{"product_id": product.id, "quantity": 1}], "payment": {"method": "CASH"}},
    )
    client.post(f"/api/v1/cash/registers/{register_id}/close", headers=headers, json={"closing_amount": 1000})

    response = client.get(
        "/api/v1/audit", headers=factory.headers(factory.admin()), params={"user_id": caissier.id}
    )

    actions = {log["action"] for log in response.json()["items"]}
    assert {"cash.open", "sale.create", "cash.close"} <= actions


def test_audit_requires_permission(client, factory):
    response = client.get("/api/v1/audit", headers=factory.headers(factory.user(RoleName.VENDEUR)))
    assert response.status_code == 403


def test_get_audit_entry(client, factory):
    headers = factory.headers(factory.admin())
    client.post("/api/v1/stores", headers=headers, json={"name": "Magasin audité"})
    log = client.get("/api/v1/audit", headers=headers, params={"action": "store.create"}).json()["items"][0]

    response = client.get(f"/api/v1/audit/{log['id']}", headers=headers)

    assert response.status_code == 200
    assert response.json()["new_data"]["name"] == "MAGASIN AUDITÉ"
    assert client.get("/api/v1/audit/999999", headers=headers).status_code == 404
