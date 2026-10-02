from datetime import UTC, datetime, timedelta

import jwt
from sqlalchemy import select

from app.core.config import settings
from app.core.security import JWT_ALGORITHM, create_refresh_token
from app.models import AuditLog
from tests.factories import DEFAULT_PASSWORD


def login(client, username, password=DEFAULT_PASSWORD):
    return client.post("/api/v1/auth/login", json={"username": username, "password": password})


def test_login_returns_tokens(client, factory):
    user = factory.user(username="jean")

    response = login(client, "jean")

    assert response.status_code == 200
    body = response.json()
    assert body["token_type"] == "bearer"
    assert body["access_token"] and body["refresh_token"]
    assert body["expires_in"] == settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES * 60
    me = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {body['access_token']}"})
    assert me.json()["id"] == user.id


def test_login_is_case_insensitive(client, factory):
    factory.user(username="Jean.Dupont")
    assert login(client, "JEAN.DUPONT").status_code == 200
    assert login(client, "jean.dupont").status_code == 200


def test_login_with_wrong_password_is_rejected_and_audited(client, factory, db):
    user = factory.user(username="marie")

    response = login(client, "marie", "mauvais-mot-de-passe")

    assert response.status_code == 401
    assert response.json()["code"] == "INVALID_CREDENTIALS"
    log = db.scalar(select(AuditLog).where(AuditLog.action == "auth.login_failed"))
    assert log is not None and log.user_id == user.id


def test_login_with_unknown_user_is_rejected(client):
    response = login(client, "inconnu")
    assert response.status_code == 401
    assert response.json()["detail"] == "Nom d'utilisateur ou mot de passe incorrect"


def test_inactive_user_cannot_login(client, factory):
    factory.user(username="ancien", is_active=False)

    response = login(client, "ancien")

    assert response.status_code == 403
    assert response.json()["code"] == "ACCOUNT_DISABLED"


def test_successful_login_is_audited(client, factory, db):
    user = factory.user(username="paul")
    login(client, "paul")
    log = db.scalar(select(AuditLog).where(AuditLog.action == "auth.login", AuditLog.user_id == user.id))
    assert log is not None
    assert log.ip_address == "testclient"


def test_me_returns_profile_with_permissions_without_password(client, factory):
    user = factory.user(first_name="Jean", last_name="Rakoto")

    response = client.get("/api/v1/auth/me", headers=factory.headers(user))

    body = response.json()
    assert response.status_code == 200
    assert "password_hash" not in body and "password" not in body
    assert body["role"]["name"] == "vendeur"
    assert "sale.create" in body["permissions"]
    assert "sale.discount" not in body["permissions"]
    # Stocké en MAJUSCULES, affiché en minuscules.
    assert body["first_name"] == "jean" and body["last_name"] == "rakoto"
    assert user.first_name == "JEAN"


def test_admin_profile_has_every_permission(client, factory):
    body = client.get("/api/v1/auth/me", headers=factory.headers(factory.admin())).json()
    assert {"sale.discount", "user.delete", "audit.view", "stock.transfer"} <= set(body["permissions"])


def test_me_requires_authentication(client):
    response = client.get("/api/v1/auth/me")
    assert response.status_code == 401
    assert response.json()["code"] == "NOT_AUTHENTICATED"


def test_invalid_and_expired_tokens_are_rejected(client, factory):
    user = factory.user()
    expired = jwt.encode(
        {"sub": str(user.id), "type": "access", "exp": datetime.now(UTC) - timedelta(minutes=1)},
        settings.JWT_SECRET_KEY,
        algorithm=JWT_ALGORITHM,
    )

    assert client.get("/api/v1/auth/me", headers={"Authorization": "Bearer abc"}).status_code == 401
    response = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {expired}"})
    assert response.status_code == 401
    assert response.json()["code"] == "TOKEN_EXPIRED"


def test_refresh_token_cannot_be_used_as_access_token(client, factory):
    user = factory.user()
    headers = {"Authorization": f"Bearer {create_refresh_token(user.id)}"}
    assert client.get("/api/v1/auth/me", headers=headers).status_code == 401


def test_refresh_returns_new_tokens(client, factory):
    factory.user(username="luc")
    refresh_token = login(client, "luc").json()["refresh_token"]

    response = client.post("/api/v1/auth/refresh", json={"refresh_token": refresh_token})

    assert response.status_code == 200
    assert response.json()["access_token"]


def test_refresh_is_refused_for_deactivated_user(client, factory, db):
    user = factory.user()
    refresh_token = create_refresh_token(user.id)
    user.is_active = False
    db.commit()

    response = client.post("/api/v1/auth/refresh", json={"refresh_token": refresh_token})

    assert response.status_code == 401


def test_deactivated_user_token_is_refused(client, factory, db):
    user = factory.user()
    headers = factory.headers(user)
    user.is_active = False
    db.commit()

    assert client.get("/api/v1/auth/me", headers=headers).status_code == 401
