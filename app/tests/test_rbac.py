"""Rôles, permissions et isolation des magasins."""

import pytest

from app.core.permissions import PermissionCode, RoleName
from app.repositories import role_repository
from app.tests.helpers import sale_payload


def test_protected_route_requires_authentication(client):
    assert client.get("/api/v1/products").status_code == 401


def test_vendeur_default_permissions(client, factory):
    headers = factory.headers(factory.vendeur(factory.store()))

    allowed = [
        "/api/v1/products",
        "/api/v1/stock",
        "/api/v1/sales/history",
        "/api/v1/customers",
        "/api/v1/payments",
    ]
    forbidden = [
        "/api/v1/users",
        "/api/v1/audit",
        "/api/v1/stores",
        "/api/v1/cash/registers",
        "/api/v1/dashboard/summary",
    ]
    for url in allowed:
        assert client.get(url, headers=headers).status_code == 200, url
    for url in forbidden:
        assert client.get(url, headers=headers).status_code == 403, url


def test_permission_denied_message(client, factory):
    response = client.get("/api/v1/audit", headers=factory.headers(factory.vendeur(factory.store())))
    assert response.json() == {"detail": "Permission requise : audit.view", "code": "PERMISSION_DENIED"}


def test_admin_assigns_permissions_and_they_take_effect(client, factory, admin_headers, db):
    vendeur_headers = factory.headers(factory.vendeur(factory.store()))
    vendeur_role = factory.role(RoleName.VENDEUR)
    current_ids = [permission.id for permission in vendeur_role.permissions]
    dashboard_view = role_repository.get_permissions_by_names(db, ["dashboard.view"])[0]
    assert client.get("/api/v1/dashboard/summary", headers=vendeur_headers).status_code == 403

    response = client.put(
        f"/api/v1/roles/{vendeur_role.id}/permissions",
        headers=admin_headers,
        json={"permission_ids": [*current_ids, dashboard_view.id]},
    )

    assert response.status_code == 200
    assert client.get("/api/v1/dashboard/summary", headers=vendeur_headers).status_code == 200


def test_admin_permissions_are_data_driven_but_keep_assignment_rights(client, factory, admin_headers, db):
    admin_role = factory.role(RoleName.ADMIN)
    keep = role_repository.get_permissions_by_names(db, ["permission.view", "permission.assign", "role.view"])

    locked_out = client.put(
        f"/api/v1/roles/{admin_role.id}/permissions", headers=admin_headers, json={"permission_ids": []}
    )
    reduced = client.put(
        f"/api/v1/roles/{admin_role.id}/permissions",
        headers=admin_headers,
        json={"permission_ids": [permission.id for permission in keep]},
    )

    assert locked_out.status_code == 400
    assert reduced.status_code == 200
    assert (
        client.get("/api/v1/audit", headers=admin_headers).status_code == 403
    )  # l'ADMIN dépend de ses permissions


def test_list_permissions(client, admin_headers):
    names = {
        permission["name"] for permission in client.get("/api/v1/permissions", headers=admin_headers).json()
    }
    assert names == {code.value for code in PermissionCode}


def test_role_description_can_be_updated(client, factory, admin_headers):
    role = factory.role(RoleName.VENDEUR)
    response = client.put(
        f"/api/v1/roles/{role.id}", headers=admin_headers, json={"description": "Vente en boutique"}
    )
    assert response.json()["description"] == "vente en boutique"


# --- Isolation des magasins ----------------------------------------------------------------------


@pytest.fixture
def two_stores(factory):
    return factory.store("Magasin 1"), factory.store("Magasin 2")


def test_vendeur_cannot_sell_in_another_store(client, factory, two_stores):
    store_1, store_2 = two_stores
    product = factory.product(stock=5, store=store_2)
    headers = factory.headers(factory.vendeur(store_1))

    response = client.post(
        "/api/v1/sales", headers=headers, json=sale_payload((product, 1), store_id=store_2.id)
    )

    assert response.status_code == 403
    assert response.json()["code"] == "INVALID_STORE_ACCESS"


def test_vendeur_cannot_read_another_store_stock_or_history(client, factory, two_stores):
    store_1, store_2 = two_stores
    headers = factory.headers(factory.vendeur(store_1))

    assert client.get(f"/api/v1/stock/store/{store_1.id}", headers=headers).status_code == 200
    assert client.get(f"/api/v1/stock/store/{store_2.id}", headers=headers).status_code == 403
    assert client.get("/api/v1/stock", headers=headers, params={"store_id": store_2.id}).status_code == 403
    assert (
        client.get("/api/v1/sales/history", headers=headers, params={"store_id": store_2.id}).status_code
        == 403
    )
    assert (
        client.get("/api/v1/stock/movements", headers=headers, params={"store_id": store_2.id}).status_code
        == 403
    )


def test_vendeur_lists_are_limited_to_his_store(client, factory, two_stores):
    store_1, store_2 = two_stores
    product = factory.product()
    factory.add_stock(product, 3, store_1)
    factory.add_stock(product, 7, store_2)

    items = client.get("/api/v1/stock", headers=factory.headers(factory.vendeur(store_1))).json()["items"]

    assert [(line["store"]["id"], line["quantity"]) for line in items] == [(store_1.id, 3)]


def test_vendeur_without_store_cannot_operate(client, factory):
    product = factory.product(stock=5)
    headers = factory.headers(factory.vendeur(None))

    response = client.post("/api/v1/sales", headers=headers, json=sale_payload((product, 1)))

    assert response.status_code == 403
    assert "affecté à aucun magasin" in response.json()["detail"]


def test_admin_can_manage_several_stores(client, factory, admin_headers, two_stores):
    store_1, store_2 = two_stores
    for store in two_stores:
        factory.add_stock(factory.product(), 2, store)

    for store in (store_1, store_2):
        assert client.get(f"/api/v1/stock/store/{store.id}", headers=admin_headers).json()["total"] == 1
