from app.tests.helpers import due_date, sale_payload


def actions(client, headers, **params) -> list[str]:
    items = client.get("/api/v1/audit", headers=headers, params={"sort": "created_at", **params}).json()["items"]
    return [log["action"] for log in items]


def test_user_store_and_assignment_are_audited(client, factory, admin, admin_headers):
    store_id = client.post("/api/v1/stores", headers=admin_headers, json={"name": "Magasin audité"}).json()["id"]
    user_id = client.post(
        "/api/v1/users",
        headers=admin_headers,
        json={"first_name": "A", "last_name": "B", "username": "audite", "password": "Password123"},
    ).json()["id"]
    client.put(f"/api/v1/users/{user_id}/store", headers=admin_headers, json={"store_id": store_id})
    client.put(f"/api/v1/users/{user_id}/role", headers=admin_headers, json={"role": "ADMIN"})

    assert actions(client, admin_headers, entity_type="store") == ["store.create"]
    assert actions(client, admin_headers, entity_type="user", entity_id=user_id) == [
        "user.create",
        "user.store_change",
        "user.role_change",
    ]


def test_audit_never_contains_password_or_hash(client, admin_headers):
    client.post(
        "/api/v1/users",
        headers=admin_headers,
        json={"first_name": "A", "last_name": "B", "username": "secret", "password": "MotDePasseSecret1"},
    )
    logs = client.get("/api/v1/audit", headers=admin_headers, params={"action": "user.create"}).json()["items"]
    assert "MotDePasseSecret1" not in str(logs) and "password_hash" not in str(logs)


def test_stock_transfer_sale_and_payment_are_audited(client, factory, admin, admin_headers):
    shop = factory.store()
    product = factory.product(selling_price="1000", stock=10)
    client.post("/api/v1/stock/entry", headers=admin_headers, json={"product_id": product.id, "quantity": 5})
    client.post(
        "/api/v1/stock-transfers",
        headers=admin_headers,
        json={"destination_store_id": shop.id, "items": [{"product_id": product.id, "quantity": 2}]},
    )
    sale = client.post(
        "/api/v1/sales", headers=admin_headers, json=sale_payload((product, 2), payment=None, payment_due_date=due_date())
    ).json()
    client.post("/api/v1/payments", headers=admin_headers, json={"sale_id": sale["id"], "method": "CARD", "amount": 500})

    recorded = actions(client, admin_headers, user_id=admin.id)

    for action in ("stock.entry", "stock_transfer.create", "customer.create", "sale.create", "payment.create"):
        assert action in recorded, action


def test_audit_entry_detail_and_permission(client, factory, admin_headers):
    client.post("/api/v1/stores", headers=admin_headers, json={"name": "Magasin X"})
    log = client.get("/api/v1/audit", headers=admin_headers, params={"action": "store.create"}).json()["items"][0]

    assert client.get(f"/api/v1/audit/{log['id']}", headers=admin_headers).json()["new_data"]["name"] == "MAGASIN X"
    assert log["ip_address"] == "testclient"
    vendeur_headers = factory.headers(factory.vendeur(factory.store()))
    assert client.get("/api/v1/audit", headers=vendeur_headers).status_code == 403
