from sqlalchemy import select, text

from app.core.permissions import RoleName
from app.models import AuditLog, Product


def product_payload(**fields):
    return {
        "reference": "p-001",
        "name": "Riz Makalioka 1kg",
        "purchase_price": 2500,
        "selling_price": 3200,
        **fields,
    }


def test_create_product_starts_with_zero_stock(client, factory, db):
    category = factory.category("Épicerie")

    response = client.post(
        "/api/v1/products",
        headers=factory.headers(factory.admin()),
        json=product_payload(category_id=category.id, stock=500),  # le stock envoyé est ignoré
    )

    assert response.status_code == 201
    body = response.json()
    assert body["stock"] == 0
    assert body["reference"] == "p-001" and body["name"] == "riz makalioka 1kg"
    assert body["category"] == {"id": category.id, "name": "épicerie"}
    assert body["selling_price"] == 3200.0
    stored = db.execute(text("SELECT reference, name FROM products WHERE id = :id"), {"id": body["id"]}).one()
    assert tuple(stored) == ("P-001", "RIZ MAKALIOKA 1KG")


def test_reference_must_be_unique_case_insensitive(client, factory):
    factory.product(reference="P-001")
    response = client.post(
        "/api/v1/products", headers=factory.headers(factory.admin()), json=product_payload()
    )
    assert response.status_code == 409
    assert response.json()["code"] == "CONFLICT"


def test_negative_price_is_rejected(client, factory):
    response = client.post(
        "/api/v1/products", headers=factory.headers(factory.admin()), json=product_payload(selling_price=-1)
    )
    assert response.status_code == 422
    assert response.json()["errors"][0]["field"] == "body.selling_price"


def test_inactive_category_is_rejected(client, factory):
    category = factory.category(is_active=False)
    response = client.post(
        "/api/v1/products",
        headers=factory.headers(factory.admin()),
        json=product_payload(category_id=category.id),
    )
    assert response.status_code == 400


def test_update_product_is_audited_and_cannot_change_stock(client, factory, db):
    product = factory.product(selling_price="1000", stock=7)

    response = client.patch(
        f"/api/v1/products/{product.id}",
        headers=factory.headers(factory.admin()),
        json={"selling_price": 1500, "stock": 999},
    )

    assert response.status_code == 200
    assert response.json()["selling_price"] == 1500.0
    assert response.json()["stock"] == 7
    log = db.scalar(
        select(AuditLog).where(AuditLog.action == "product.update", AuditLog.entity_id == product.id)
    )
    assert log.old_data["selling_price"] == 1000.0 and log.new_data["selling_price"] == 1500.0


def test_delete_product_deactivates_it(client, factory, db):
    product = factory.product()
    response = client.delete(f"/api/v1/products/{product.id}", headers=factory.headers(factory.admin()))
    assert response.status_code == 204
    assert db.get(Product, product.id).is_active is False


def test_list_products_search_filter_and_pagination(client, factory):
    category = factory.category()
    for index in range(3):
        factory.product(name=f"Savon {index}", category_id=category.id)
    factory.product(name="Bougie")
    headers = factory.headers(factory.admin())

    page = client.get(
        "/api/v1/products", headers=headers, params={"search": "savon", "size": 2, "sort": "-name"}
    ).json()
    by_category = client.get("/api/v1/products", headers=headers, params={"category_id": category.id}).json()

    assert page["total"] == 3 and page["pages"] == 2
    assert [p["name"] for p in page["items"]] == ["savon 2", "savon 1"]
    assert by_category["total"] == 3


def test_search_escapes_like_wildcards(client, factory):
    factory.product(name="Remise 50%")
    factory.product(name="Remise 50 ans")
    response = client.get(
        "/api/v1/products", headers=factory.headers(factory.admin()), params={"search": "50%"}
    )
    assert [p["name"] for p in response.json()["items"]] == ["remise 50%"]


def test_invalid_sort_field_is_rejected(client, factory):
    response = client.get(
        "/api/v1/products", headers=factory.headers(factory.admin()), params={"sort": "password"}
    )
    assert response.status_code == 400
    assert response.json()["code"] == "INVALID_SORT"


def test_vendeur_can_view_but_not_create_products(client, factory):
    headers = factory.headers(factory.user(RoleName.VENDEUR))
    assert client.get("/api/v1/products", headers=headers).status_code == 200
    assert client.post("/api/v1/products", headers=headers, json=product_payload()).status_code == 403


def test_category_crud(client, factory):
    headers = factory.headers(factory.admin())

    created = client.post(
        "/api/v1/categories", headers=headers, json={"name": "Boissons", "description": "Sodas"}
    )
    category_id = created.json()["id"]
    duplicate = client.post("/api/v1/categories", headers=headers, json={"name": "BOISSONS"})
    updated = client.patch(f"/api/v1/categories/{category_id}", headers=headers, json={"description": "Jus"})
    deleted = client.delete(f"/api/v1/categories/{category_id}", headers=headers)

    assert created.status_code == 201 and created.json()["name"] == "boissons"
    assert duplicate.status_code == 409
    assert updated.json()["description"] == "jus"
    assert deleted.status_code == 204
    assert client.get(f"/api/v1/categories/{category_id}", headers=headers).json()["is_active"] is False
