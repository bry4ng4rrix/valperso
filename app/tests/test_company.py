from sqlalchemy import select

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
