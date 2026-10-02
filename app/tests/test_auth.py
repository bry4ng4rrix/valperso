from datetime import UTC, datetime, timedelta

import jwt
from sqlalchemy import select

from app.core.config import settings
from app.core.permissions import PermissionCode, RoleName
from app.core.security import JWT_ALGORITHM, create_refresh_token
from app.models import AuditLog
from app.tests.factories import DEFAULT_PASSWORD


def login(client, username, password=DEFAULT_PASSWORD):
    return client.post("/api/v1/auth/login", json={"username": username, "password": password})


def test_login_returns_access_and_refresh_tokens(client, factory):
    user = factory.vendeur(factory.store(), username="jean")

    response = login(client, "jean")

    assert response.status_code == 200
    body = response.json()
    assert body["token_type"] == "bearer" and body["access_token"] and body["refresh_token"]
    assert body["expires_in"] == settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES * 60
    me = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {body['access_token']}"})
    assert me.json()["id"] == user.id


def test_login_is_case_insensitive(client, factory):
    factory.admin(username="Jean.Dupont")
    assert login(client, "JEAN.DUPONT").status_code == 200
    assert login(client, "jean.dupont").status_code == 200


def test_login_with_email(client, factory):
    factory.admin(username="valencia", email="valencia@local.mg")
    assert login(client, "Valencia@Local.mg").status_code == 200
    assert login(client, "inconnu@local.mg").status_code == 401


def test_wrong_password_is_rejected_and_audited_without_password(client, factory, db):
    user = factory.admin(username="marie")

    response = login(client, "marie", "mauvais-mot-de-passe")

    assert response.status_code == 401
    assert response.json()["code"] == "INVALID_CREDENTIALS"
    log = db.scalar(select(AuditLog).where(AuditLog.action == "auth.login_failed"))
    assert log.user_id == user.id
    assert "mauvais-mot-de-passe" not in str(log.new_data)


def test_unknown_user_is_rejected(client):
    assert login(client, "inconnu").status_code == 401


def test_inactive_user_cannot_login(client, factory):
    factory.vendeur(factory.store(), username="ancien", is_active=False)

    response = login(client, "ancien")

    assert response.status_code == 403
    assert response.json()["code"] == "ACCOUNT_DISABLED"


def test_successful_login_is_audited(client, factory, db):
    user = factory.admin(username="paul")
    login(client, "paul")
    log = db.scalar(select(AuditLog).where(AuditLog.action == "auth.login", AuditLog.user_id == user.id))
    assert log is not None and log.ip_address == "testclient"


def test_me_returns_profile_role_store_and_permissions(client, factory):
    store = factory.store("Magasin Analakely")
    vendeur = factory.vendeur(store, first_name="Jean", last_name="Rakoto")

    body = client.get("/api/v1/auth/me", headers=factory.headers(vendeur)).json()

    assert "password_hash" not in body and "password" not in body
    assert body["role"]["name"] == RoleName.VENDEUR
    assert body["store"]["name"] == "magasin analakely"
    assert "sale.create" in body["permissions"] and "sale.discount" not in body["permissions"]
    assert body["first_name"] == "jean" and vendeur.first_name == "JEAN"


def test_admin_profile_has_every_permission(client, factory):
    body = client.get("/api/v1/auth/me", headers=factory.headers(factory.admin())).json()
    assert set(body["permissions"]) == {code.value for code in PermissionCode}
    assert body["store_id"] is None


def test_me_requires_authentication(client):
    response = client.get("/api/v1/auth/me")
    assert response.status_code == 401
    assert response.json()["code"] == "NOT_AUTHENTICATED"


def test_invalid_and_expired_tokens_are_rejected(client, factory):
    user = factory.admin()
    expired = jwt.encode(
        {"sub": str(user.id), "type": "access", "exp": datetime.now(UTC) - timedelta(minutes=1)},
        settings.JWT_SECRET_KEY,
        algorithm=JWT_ALGORITHM,
    )
    assert client.get("/api/v1/auth/me", headers={"Authorization": "Bearer abc"}).status_code == 401
    response = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {expired}"})
    assert response.json()["code"] == "TOKEN_EXPIRED"


def test_refresh_token_cannot_be_used_as_access_token(client, factory):
    headers = {"Authorization": f"Bearer {create_refresh_token(factory.admin().id)}"}
    assert client.get("/api/v1/auth/me", headers=headers).status_code == 401


def test_refresh_returns_new_tokens(client, factory):
    factory.admin(username="luc")
    refresh_token = login(client, "luc").json()["refresh_token"]

    response = client.post("/api/v1/auth/refresh", json={"refresh_token": refresh_token})

    assert response.status_code == 200 and response.json()["access_token"]


def test_refresh_and_access_are_refused_for_deactivated_user(client, factory, db):
    user = factory.admin()
    headers = factory.headers(user)
    refresh_token = create_refresh_token(user.id)
    user.is_active = False
    db.commit()

    assert client.post("/api/v1/auth/refresh", json={"refresh_token": refresh_token}).status_code == 401
    assert client.get("/api/v1/auth/me", headers=headers).status_code == 401
