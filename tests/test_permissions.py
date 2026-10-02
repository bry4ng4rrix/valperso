from sqlalchemy import select

from app.core.permissions import PermissionCode, RoleName
from app.models import AuditLog
from app.repositories import role_repository


def test_protected_route_requires_authentication(client):
    assert client.get("/api/v1/products").status_code == 401


def test_user_without_permission_gets_403(client, factory):
    magasinier = factory.user(RoleName.MAGASINIER)

    response = client.get("/api/v1/sales", headers=factory.headers(magasinier))

    assert response.status_code == 403
    assert response.json() == {"detail": "Permission requise : sale.view", "code": "PERMISSION_DENIED"}


def test_role_grants_only_its_permissions(client, factory):
    user = factory.user(factory.role(PermissionCode.PRODUCT_VIEW))
    headers = factory.headers(user)

    assert client.get("/api/v1/products", headers=headers).status_code == 200
    created = client.post(
        "/api/v1/products",
        headers=headers,
        json={"reference": "X1", "name": "Test", "purchase_price": 1, "selling_price": 2},
    )
    assert created.status_code == 403


def test_admin_has_every_permission_even_without_explicit_grant(client, factory):
    assert client.get("/api/v1/audit", headers=factory.headers(factory.admin())).status_code == 200


def test_list_permissions(client, factory):
    response = client.get("/api/v1/permissions", headers=factory.headers(factory.admin()))
    names = {permission["name"] for permission in response.json()}
    assert names == {code.value for code in PermissionCode}


def test_updating_role_permissions_changes_access_and_is_audited(client, factory, db):
    role = factory.role(PermissionCode.PRODUCT_VIEW)
    user_headers = factory.headers(factory.user(role))
    sale_view = role_repository.get_permissions_by_names(db, ["sale.view"])[0]
    assert client.get("/api/v1/sales", headers=user_headers).status_code == 403

    response = client.put(
        f"/api/v1/roles/{role.id}/permissions",
        headers=factory.headers(factory.admin()),
        json={"permission_ids": [sale_view.id]},
    )

    assert response.status_code == 200
    assert [p["name"] for p in response.json()["permissions"]] == ["sale.view"]
    assert client.get("/api/v1/sales", headers=user_headers).status_code == 200
    assert client.get("/api/v1/products", headers=user_headers).status_code == 403
    log = db.scalar(select(AuditLog).where(AuditLog.action == "role.permissions_update"))
    assert log.old_data["permissions"][0]["name"] == "product.view"


def test_admin_role_permissions_cannot_be_changed(client, factory, db):
    admin_role = role_repository.get_by_name(db, RoleName.ADMIN)
    response = client.put(
        f"/api/v1/roles/{admin_role.id}/permissions",
        headers=factory.headers(factory.admin()),
        json={"permission_ids": []},
    )
    assert response.status_code == 400


def test_unknown_permission_id_is_rejected(client, factory):
    role = factory.role()
    response = client.put(
        f"/api/v1/roles/{role.id}/permissions",
        headers=factory.headers(factory.admin()),
        json={"permission_ids": [999999]},
    )
    assert response.status_code == 404


def test_create_role_is_stored_uppercase_and_displayed_lowercase(client, factory, db):
    response = client.post(
        "/api/v1/roles",
        headers=factory.headers(factory.admin()),
        json={"name": "chef_rayon", "description": "Chef de rayon"},
    )
    assert response.status_code == 201
    assert response.json()["name"] == "chef_rayon"
    assert role_repository.get_by_name(db, "CHEF_RAYON").description == "CHEF DE RAYON"


def test_system_roles_cannot_be_deleted_or_renamed(client, factory, db):
    headers = factory.headers(factory.admin())
    vendeur = role_repository.get_by_name(db, RoleName.VENDEUR)

    assert client.delete(f"/api/v1/roles/{vendeur.id}", headers=headers).status_code == 400
    assert (
        client.patch(f"/api/v1/roles/{vendeur.id}", headers=headers, json={"name": "autre"}).status_code
        == 400
    )


def test_role_in_use_cannot_be_deleted(client, factory):
    role = factory.role()
    factory.user(role)
    headers = factory.headers(factory.admin())

    assert client.delete(f"/api/v1/roles/{role.id}", headers=headers).status_code == 400


def test_unused_custom_role_can_be_deleted(client, factory):
    role = factory.role()
    headers = factory.headers(factory.admin())

    assert client.delete(f"/api/v1/roles/{role.id}", headers=headers).status_code == 204
    assert client.get(f"/api/v1/roles/{role.id}", headers=headers).status_code == 404


def test_non_admin_cannot_create_an_admin(client, factory, db):
    manager_like = factory.user(factory.role(PermissionCode.USER_CREATE))
    admin_role = role_repository.get_by_name(db, RoleName.ADMIN)

    response = client.post(
        "/api/v1/users",
        headers=factory.headers(manager_like),
        json={
            "first_name": "Pirate",
            "last_name": "Test",
            "username": "pirate",
            "password": "Password123",
            "role_id": admin_role.id,
        },
    )

    assert response.status_code == 403


def test_store_scoped_user_cannot_access_another_store(client, factory):
    store_a, store_b = factory.store(), factory.store()
    vendeur = factory.user(RoleName.VENDEUR, store_a)
    headers = factory.headers(vendeur)

    assert client.get(f"/api/v1/stores/{store_a.id}/stock", headers=headers).status_code == 200
    response = client.get(f"/api/v1/stores/{store_b.id}/stock", headers=headers)
    assert response.status_code == 403
    assert response.json()["code"] == "STORE_ACCESS_DENIED"
