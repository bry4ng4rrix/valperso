from sqlalchemy import select

from app.core.permissions import PermissionCode, RoleName
from app.models import AuditLog, User


def user_payload(**fields):
    return {
        "first_name": "Hery",
        "last_name": "Rabe",
        "username": "hery.rabe",
        "email": "Hery.Rabe@Example.com",
        "password": "Password123",
        **fields,
    }


def test_admin_creates_a_vendeur_assigned_to_a_store(client, factory, admin_headers, db):
    store = factory.store()

    response = client.post("/api/v1/users", headers=admin_headers, json=user_payload(store_id=store.id))

    assert response.status_code == 201
    body = response.json()
    assert "password" not in body and "password_hash" not in body
    assert body["role"]["name"] == "VENDEUR" and body["store_id"] == store.id
    assert body["username"] == "hery.rabe" and body["email"] == "hery.rabe@example.com"
    assert db.get(User, body["id"]).username == "HERY.RABE"


def test_admin_can_create_several_other_admins(client, admin_headers):
    first = client.post("/api/v1/users", headers=admin_headers, json=user_payload(username="co1", email=None, role="ADMIN"))
    second = client.post("/api/v1/users", headers=admin_headers, json=user_payload(username="co2", email=None, role="ADMIN"))

    assert first.status_code == second.status_code == 201
    assert first.json()["role"]["name"] == "ADMIN" and first.json()["store_id"] is None
    co_admin_token = client.post("/api/v1/auth/login", json={"username": "co1", "password": "Password123"})
    headers = {"Authorization": f"Bearer {co_admin_token.json()['access_token']}"}
    third = client.post("/api/v1/users", headers=headers, json=user_payload(username="co3", email=None, role="ADMIN"))
    assert third.status_code == 201


def test_only_two_roles_exist(client, admin_headers):
    roles = client.get("/api/v1/roles", headers=admin_headers).json()
    assert sorted(role["name"] for role in roles) == ["ADMIN", "VENDEUR"]
    response = client.post("/api/v1/users", headers=admin_headers, json=user_payload(role="MANAGER"))
    assert response.status_code == 422


def test_username_must_be_unique_case_insensitive(client, factory, admin_headers):
    factory.vendeur(None, username="HERY.RABE")
    assert client.post("/api/v1/users", headers=admin_headers, json=user_payload()).status_code == 409


def test_invalid_user_data_returns_clear_errors(client, admin_headers):
    response = client.post("/api/v1/users", headers=admin_headers, json=user_payload(password="court", email="x"))
    assert response.status_code == 422
    assert {error["field"] for error in response.json()["errors"]} == {"body.password", "body.email"}


def test_update_user_information(client, factory, admin_headers):
    vendeur = factory.vendeur(factory.store(), username="tiana")

    response = client.put(
        f"/api/v1/users/{vendeur.id}",
        headers=admin_headers,
        json={"first_name": "Tiana", "last_name": "Rasoa", "username": "tiana.r", "phone": "0331112233",
              "password": "NouveauMdp456"},
    )  # fmt: skip

    assert response.status_code == 200
    assert response.json()["username"] == "tiana.r" and response.json()["phone"] == "0331112233"
    login = client.post("/api/v1/auth/login", json={"username": "tiana.r", "password": "NouveauMdp456"})
    assert login.status_code == 200


def test_change_role(client, factory, admin_headers, db):
    vendeur = factory.vendeur(factory.store())

    response = client.put(f"/api/v1/users/{vendeur.id}/role", headers=admin_headers, json={"role": "ADMIN"})

    assert response.status_code == 200 and response.json()["role"]["name"] == "ADMIN"
    log = db.scalar(select(AuditLog).where(AuditLog.action == "user.role_change"))
    assert log.old_data["role"]["name"] == "VENDEUR" and log.new_data["role"]["name"] == "ADMIN"


def test_assign_change_and_remove_store(client, factory, admin_headers, db):
    store_1, store_2 = factory.store(), factory.store()
    vendeur = factory.vendeur(None)
    url = f"/api/v1/users/{vendeur.id}/store"

    assigned = client.put(url, headers=admin_headers, json={"store_id": store_1.id})
    moved = client.put(url, headers=admin_headers, json={"store_id": store_2.id})
    removed = client.put(url, headers=admin_headers, json={"store_id": None})

    assert assigned.json()["store_id"] == store_1.id
    assert moved.json()["store_id"] == store_2.id
    assert removed.json()["store_id"] is None
    logs = db.scalars(select(AuditLog).where(AuditLog.action == "user.store_change")).all()
    assert [log.new_data["store_id"] for log in logs] == [store_1.id, store_2.id, None]


def test_cannot_assign_to_inactive_or_unknown_store(client, factory, admin_headers):
    vendeur = factory.vendeur(None)
    url = f"/api/v1/users/{vendeur.id}/store"
    assert client.put(url, headers=admin_headers, json={"store_id": factory.store(is_active=False).id}).status_code == 400
    assert client.put(url, headers=admin_headers, json={"store_id": 999999}).status_code == 404


def test_deactivate_and_reactivate_account(client, factory, admin_headers):
    vendeur = factory.vendeur(factory.store(), username="partant")
    url = f"/api/v1/users/{vendeur.id}/status"

    assert client.put(url, headers=admin_headers, json={"is_active": False}).json()["is_active"] is False
    assert client.post("/api/v1/auth/login", json={"username": "partant", "password": "Password123"}).status_code == 403
    assert client.put(url, headers=admin_headers, json={"is_active": True}).json()["is_active"] is True
    assert client.post("/api/v1/auth/login", json={"username": "partant", "password": "Password123"}).status_code == 200


def test_delete_user_deactivates_the_account(client, factory, admin_headers, db):
    vendeur = factory.vendeur(factory.store())
    assert client.delete(f"/api/v1/users/{vendeur.id}", headers=admin_headers).status_code == 204
    db.refresh(vendeur)
    assert vendeur.is_active is False


def test_admin_cannot_deactivate_himself(client, admin, admin_headers):
    response = client.put(f"/api/v1/users/{admin.id}/status", headers=admin_headers, json={"is_active": False})
    assert response.status_code == 400


def test_last_active_admin_cannot_be_demoted_or_deactivated(client, factory, admin, admin_headers):
    other_admin = factory.admin()
    other_headers = factory.headers(other_admin)
    # Deux ADMIN : l'un peut rétrograder l'autre.
    assert client.put(f"/api/v1/users/{admin.id}/role", headers=other_headers, json={"role": "VENDEUR"}).status_code == 200
    # other_admin est maintenant le dernier ADMIN actif : il ne peut pas être rétrogradé.
    response = client.put(f"/api/v1/users/{other_admin.id}/role", headers=other_headers, json={"role": "VENDEUR"})
    assert response.status_code == 400


def test_vendeur_cannot_manage_users(client, factory):
    headers = factory.headers(factory.vendeur(factory.store()))
    assert client.get("/api/v1/users", headers=headers).status_code == 403
    assert client.post("/api/v1/users", headers=headers, json=user_payload()).status_code == 403


def test_user_with_user_create_permission_but_not_admin_cannot_create_admin(client, factory):
    factory.grant(RoleName.VENDEUR, PermissionCode.USER_CREATE)
    headers = factory.headers(factory.vendeur(factory.store()))
    response = client.post("/api/v1/users", headers=headers, json=user_payload(role="ADMIN", email=None))
    assert response.status_code == 403


def test_list_users_filters(client, factory, admin_headers):
    store = factory.store()
    factory.vendeur(store, username="rakoto.jean", first_name="Jean")
    factory.vendeur(store, username="rabe.paul", is_active=False)
    factory.vendeur(factory.store(), username="autre")

    def usernames(**params):
        items = client.get("/api/v1/users", headers=admin_headers, params=params).json()["items"]
        return sorted(user["username"] for user in items)

    assert usernames(store_id=store.id) == ["rabe.paul", "rakoto.jean"]
    assert usernames(store_id=store.id, is_active=True) == ["rakoto.jean"]
    assert usernames(search="jean") == ["rakoto.jean"]
    assert "rakoto.jean" in usernames(role="VENDEUR") and "rakoto.jean" not in usernames(role="ADMIN")


def test_store_employees(client, factory, admin_headers):
    store = factory.store()
    factory.vendeur(store, username="employe1")
    factory.vendeur(store, username="employe2")
    factory.vendeur(factory.store(), username="ailleurs")

    response = client.get(f"/api/v1/stores/{store.id}/employees", headers=admin_headers)

    assert sorted(user["username"] for user in response.json()["items"]) == ["employe1", "employe2"]
