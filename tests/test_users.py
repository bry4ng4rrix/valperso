from app.core.permissions import RoleName
from app.models import User
from app.repositories import role_repository


def user_payload(db, **fields):
    role = role_repository.get_by_name(db, RoleName.CAISSIER)
    return {
        "first_name": "Hery",
        "last_name": "Rabe",
        "username": "hery.rabe",
        "email": "Hery.Rabe@Example.com",
        "password": "Password123",
        "role_id": role.id,
        **fields,
    }


def test_create_user(client, factory, db):
    store = factory.store()

    response = client.post(
        "/api/v1/users", headers=factory.headers(factory.admin()), json=user_payload(db, store_id=store.id)
    )

    assert response.status_code == 201
    body = response.json()
    assert "password" not in body and "password_hash" not in body
    assert body["username"] == "hery.rabe"
    assert body["email"] == "hery.rabe@example.com"
    assert body["role"]["name"] == "caissier"
    assert body["store_id"] == store.id
    user = db.get(User, body["id"])
    assert user.username == "HERY.RABE" and user.first_name == "HERY"
    assert user.password_hash != "Password123"


def test_username_must_be_unique_case_insensitive(client, factory, db):
    factory.user(username="HERY.RABE")
    response = client.post("/api/v1/users", headers=factory.headers(factory.admin()), json=user_payload(db))
    assert response.status_code == 409


def test_invalid_user_data_returns_clear_errors(client, factory, db):
    response = client.post(
        "/api/v1/users",
        headers=factory.headers(factory.admin()),
        json=user_payload(db, password="court", email="pas-un-email"),
    )

    assert response.status_code == 422
    body = response.json()
    assert body["code"] == "VALIDATION_ERROR"
    assert {error["field"] for error in body["errors"]} == {"body.password", "body.email"}


def test_update_user_role_and_password(client, factory, db):
    user = factory.user(RoleName.VENDEUR, username="tiana")
    manager_role = role_repository.get_by_name(db, RoleName.MANAGER)

    response = client.patch(
        f"/api/v1/users/{user.id}",
        headers=factory.headers(factory.admin()),
        json={"role_id": manager_role.id, "password": "NouveauMdp456"},
    )

    assert response.status_code == 200
    assert response.json()["role"]["name"] == "manager"
    login = client.post("/api/v1/auth/login", json={"username": "tiana", "password": "NouveauMdp456"})
    assert login.status_code == 200


def test_required_fields_cannot_be_set_to_null(client, factory):
    user = factory.user()
    response = client.patch(
        f"/api/v1/users/{user.id}", headers=factory.headers(factory.admin()), json={"first_name": None}
    )
    assert response.status_code == 422


def test_user_cannot_deactivate_or_delete_himself(client, factory):
    admin = factory.admin()
    headers = factory.headers(admin)

    assert (
        client.patch(f"/api/v1/users/{admin.id}", headers=headers, json={"is_active": False}).status_code
        == 400
    )
    assert client.delete(f"/api/v1/users/{admin.id}", headers=headers).status_code == 400


def test_delete_user_deactivates_account(client, factory, db):
    user = factory.user(username="partant")

    response = client.delete(f"/api/v1/users/{user.id}", headers=factory.headers(factory.admin()))

    assert response.status_code == 204
    db.refresh(user)
    assert user.is_active is False
    login = client.post("/api/v1/auth/login", json={"username": "partant", "password": "Password123"})
    assert login.status_code == 403


def test_list_users_with_search(client, factory):
    factory.user(username="rakoto.jean", last_name="Rakoto")
    factory.user(username="rabe.paul", last_name="Rabe")

    response = client.get(
        "/api/v1/users", headers=factory.headers(factory.admin()), params={"search": "rakoto"}
    )

    assert response.status_code == 200
    assert [u["username"] for u in response.json()["items"]] == ["rakoto.jean"]
