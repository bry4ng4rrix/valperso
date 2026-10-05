import pytest
from sqlalchemy import select

from app.core.config import settings
from app.main import app
from app.models import AuditLog

ALLSAFE = {
    "name": "Allsafe",
    "logo_url": "https://cdn.exemple.mg/allsafe/logo.png",
    "phone": "034 12 345 67",
    "email": "Contact@Allsafe.mg",
    "address": "Boutique H101",
    "city": "Antananarivo",
}


def test_get_company(client, factory, admin_headers):
    factory.company(name="ALLSAFE", city="ANTANANARIVO")

    body = client.get("/api/v1/company", headers=admin_headers).json()

    assert body["name"] == "allsafe" and body["city"] == "antananarivo"


def test_admin_updates_every_field(client, admin_headers):
    response = client.put("/api/v1/company", headers=admin_headers, json=ALLSAFE)

    assert response.status_code == 200
    body = response.json()
    assert (body["name"], body["address"], body["city"]) == ("allsafe", "boutique h101", "antananarivo")
    assert (body["phone"], body["email"]) == ("034 12 345 67", "contact@allsafe.mg")
    assert body["logo_url"] == ALLSAFE["logo_url"]  # une URL est conservée telle quelle


def test_logo_can_be_replaced_or_removed(client, admin_headers):
    client.put("/api/v1/company", headers=admin_headers, json=ALLSAFE)

    replaced = client.put(
        "/api/v1/company", headers=admin_headers, json={**ALLSAFE, "logo_url": "/media/logo-v2.png"}
    )
    removed = client.put("/api/v1/company", headers=admin_headers, json={**ALLSAFE, "logo_url": None})

    assert replaced.json()["logo_url"] == "/media/logo-v2.png"
    assert removed.json()["logo_url"] is None


def test_invalid_logo_is_rejected(client, admin_headers):
    response = client.put(
        "/api/v1/company", headers=admin_headers, json={**ALLSAFE, "logo_url": "logo sans chemin"}
    )
    assert response.status_code == 422


def test_vendeur_can_read_but_not_update(client, factory):
    headers = factory.headers(factory.vendeur(factory.store()))
    assert client.get("/api/v1/company", headers=headers).status_code == 200
    response = client.put("/api/v1/company", headers=headers, json=ALLSAFE)
    assert response.status_code == 403 and response.json()["detail"] == "Permission requise : company.update"


def test_update_is_audited_with_old_and_new_values(client, admin, admin_headers, db):
    client.put("/api/v1/company", headers=admin_headers, json=ALLSAFE)
    client.put("/api/v1/company", headers=admin_headers, json={**ALLSAFE, "name": "Allsafe Madagascar"})

    log = db.scalars(
        select(AuditLog).where(AuditLog.action == "company.update").order_by(AuditLog.id.desc())
    ).first()

    assert log.user_id == admin.id and log.ip_address == "testclient" and log.created_at
    assert (log.old_data["name"], log.new_data["name"]) == ("ALLSAFE", "ALLSAFE MADAGASCAR")


# --- Logo envoyé depuis l'application -------------------------------------------------------------

PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64


@pytest.fixture
def media_dir(tmp_path, monkeypatch):
    """Les fichiers des tests vont dans un dossier temporaire, servi aussi sous /media."""
    monkeypatch.setattr(settings, "MEDIA_ROOT", str(tmp_path))
    mount = next(route.app for route in app.routes if getattr(route, "path", None) == "/media")
    monkeypatch.setattr(mount, "all_directories", [tmp_path])
    return tmp_path


def upload_logo(client, headers, content, name="logo.png"):
    return client.post("/api/v1/company/logo", headers=headers, files={"file": (name, content, "image/png")})


def test_uploaded_logo_is_saved_served_and_used(client, admin_headers, media_dir):
    response = upload_logo(client, admin_headers, PNG)

    assert response.status_code == 200, response.text
    logo_url = response.json()["logo_url"]
    assert logo_url.startswith("/media/company/") and logo_url.endswith(".png")
    assert client.get(logo_url).content == PNG
    assert client.get("/api/v1/company", headers=admin_headers).json()["logo_url"] == logo_url


def test_replacing_the_logo_keeps_the_old_file_for_past_invoices(client, admin_headers, media_dir):
    first = upload_logo(client, admin_headers, PNG).json()["logo_url"]
    second = upload_logo(client, admin_headers, PNG + b"\x01").json()["logo_url"]

    assert first != second
    assert client.get(first).status_code == 200  # encore affiché sur les anciennes factures


def test_uploaded_logo_must_be_an_image(client, admin_headers, media_dir):
    response = upload_logo(client, admin_headers, b"%PDF-1.7 pas une image", name="logo.png")

    assert response.status_code == 400
    assert not (media_dir / "company").exists()


def test_vendeur_cannot_upload_the_logo(client, factory, media_dir):
    seller = factory.vendeur(factory.store())

    assert upload_logo(client, factory.headers(seller), PNG).status_code == 403
