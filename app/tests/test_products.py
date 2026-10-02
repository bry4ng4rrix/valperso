from sqlalchemy import select

from app.models import AuditLog, Product, Stock


def product_payload(**fields):
    return {"reference": "p-001", "name": "Riz Makalioka 1kg", "purchase_price": 2500, "selling_price": 3200, **fields}


def test_create_product_creates_its_stock_local_line(client, factory, admin_headers, db):
    category = factory.category("Épicerie")

    response = client.post("/api/v1/products", headers=admin_headers, json=product_payload(category_id=category.id))

    assert response.status_code == 201
    body = response.json()
    assert body["reference"] == "p-001" and body["name"] == "riz makalioka 1kg"
    assert body["category"] == {"id": category.id, "name": "épicerie"}
    assert "stock" not in body
    lines = db.scalars(select(Stock).where(Stock.product_id == body["id"])).all()
    assert [(line.store_id, line.quantity) for line in lines] == [(factory.central_store().id, 0)]


def test_same_reference_and_same_name_are_allowed(client, admin_headers):
    first = client.post("/api/v1/products", headers=admin_headers, json=product_payload())
    same_reference = client.post("/api/v1/products", headers=admin_headers, json=product_payload(name="Autre"))
    same_everything = client.post("/api/v1/products", headers=admin_headers, json=product_payload())

    assert first.status_code == same_reference.status_code == same_everything.status_code == 201
    assert len({first.json()["id"], same_reference.json()["id"], same_everything.json()["id"]}) == 3


def test_negative_price_is_rejected(client, admin_headers):
    response = client.post("/api/v1/products", headers=admin_headers, json=product_payload(selling_price=-1))
    assert response.status_code == 422
    assert response.json()["errors"][0]["field"] == "body.selling_price"


def test_inactive_category_is_rejected(client, factory, admin_headers):
    category = factory.category(is_active=False)
    response = client.post("/api/v1/products", headers=admin_headers, json=product_payload(category_id=category.id))
    assert response.status_code == 400


def test_get_update_and_audit_product(client, factory, admin_headers, db):
    product = factory.product(selling_price="1000")

    assert client.get(f"/api/v1/products/{product.id}", headers=admin_headers).json()["selling_price"] == 1000.0
    response = client.patch(f"/api/v1/products/{product.id}", headers=admin_headers, json={"selling_price": 1500})

    assert response.json()["selling_price"] == 1500.0
    log = db.scalar(select(AuditLog).where(AuditLog.action == "product.update", AuditLog.entity_id == product.id))
    assert log.old_data["selling_price"] == 1000.0 and log.new_data["selling_price"] == 1500.0


def test_delete_product_deactivates_it(client, factory, admin_headers, db):
    product = factory.product()
    assert client.delete(f"/api/v1/products/{product.id}", headers=admin_headers).status_code == 204
    assert db.get(Product, product.id).is_active is False


def test_unknown_product_returns_404(client, admin_headers):
    response = client.get("/api/v1/products/999999", headers=admin_headers)
    assert response.status_code == 404 and response.json()["code"] == "PRODUCT_NOT_FOUND"


def test_list_products_search_filter_sort_and_pagination(client, factory, admin_headers):
    category = factory.category()
    for index in range(3):
        factory.product(name=f"Savon {index}", category_id=category.id)
    factory.product(name="Bougie")

    page = client.get(
        "/api/v1/products", headers=admin_headers, params={"search": "SAVON", "page_size": 2, "sort": "-name"}
    ).json()
    by_category = client.get("/api/v1/products", headers=admin_headers, params={"category_id": category.id}).json()

    assert page["total"] == 3 and page["pages"] == 2 and page["page_size"] == 2
    assert [p["name"] for p in page["items"]] == ["savon 2", "savon 1"]
    assert by_category["total"] == 3


def test_page_size_is_limited_to_100(client, admin_headers):
    assert client.get("/api/v1/products", headers=admin_headers, params={"page_size": 101}).status_code == 422


def test_invalid_sort_field_is_rejected(client, admin_headers):
    response = client.get("/api/v1/products", headers=admin_headers, params={"sort": "password"})
    assert response.status_code == 400 and response.json()["code"] == "INVALID_SORT"


def test_vendeur_can_view_but_not_manage_products(client, factory):
    headers = factory.headers(factory.vendeur(factory.store()))
    assert client.get("/api/v1/products", headers=headers).status_code == 200
    assert client.post("/api/v1/products", headers=headers, json=product_payload()).status_code == 403


def test_category_crud(client, admin_headers):
    created = client.post("/api/v1/categories", headers=admin_headers, json={"name": "Boissons", "description": "Sodas"})
    category_id = created.json()["id"]

    duplicate = client.post("/api/v1/categories", headers=admin_headers, json={"name": "BOISSONS"})
    updated = client.patch(f"/api/v1/categories/{category_id}", headers=admin_headers, json={"description": "Jus"})
    deleted = client.delete(f"/api/v1/categories/{category_id}", headers=admin_headers)

    assert created.status_code == 201 and created.json()["name"] == "boissons"
    assert duplicate.status_code == 409
    assert updated.json()["description"] == "jus"
    assert deleted.status_code == 204
    assert client.get(f"/api/v1/categories/{category_id}", headers=admin_headers).json()["is_active"] is False
