"""Ouverture (06:00) et fermeture (19:00) automatiques des caisses, à l'heure de Madagascar."""

from datetime import UTC, datetime
from decimal import Decimal
from zoneinfo import ZoneInfo

from sqlalchemy import func, select

from app.models import AuditLog, CashRegister
from app.models.enums import CashRegisterStatus, CashTransactionType
from app.services import cash_schedule_service, cash_service
from app.tests.helpers import sale_payload

MADAGASCAR = ZoneInfo("Indian/Antananarivo")


def at(day: int, hour: int, minute: int = 0) -> datetime:
    """Heure locale de Madagascar, le `day` octobre 2026."""
    return datetime(2026, 10, day, hour, minute, tzinfo=MADAGASCAR)


def open_registers(db) -> dict[int, CashRegister]:
    registers = db.scalars(select(CashRegister).where(CashRegister.status == CashRegisterStatus.OPEN)).all()
    return {register.store_id: register for register in registers}


def register_count(db, store_id: int) -> int:
    return db.scalar(select(func.count()).select_from(CashRegister).where(CashRegister.store_id == store_id))


def test_horaires_a_l_heure_de_madagascar():
    # 03:30 UTC = 06:30 à Antananarivo (UTC+3).
    last_open, last_close = cash_schedule_service.last_boundaries(datetime(2026, 10, 3, 3, 30, tzinfo=UTC))
    assert last_open == at(3, 6)
    assert last_close == at(2, 19)
    last_open, last_close = cash_schedule_service.last_boundaries(at(3, 5, 59))
    assert last_open == at(2, 6) and last_close == at(2, 19)


def test_ouverture_automatique_de_chaque_magasin_actif_a_6h(db, factory):
    shop = factory.store()
    inactive = factory.store(is_active=False)

    result = cash_schedule_service.run(db, now=at(3, 6, 0))

    registers = open_registers(db)
    assert factory.central_store().id in registers and shop.id in registers
    assert inactive.id not in registers
    register = registers[shop.id]
    assert register.opened_automatically is True and register.opened_by is None
    assert register.opening_amount == register.expected_amount == Decimal("0")
    assert shop.id in result.opened
    audit = db.scalar(
        select(AuditLog).where(AuditLog.action == "cash.auto_open", AuditLog.entity_id == register.id)
    )
    assert audit is not None and audit.user_id is None


def test_rien_avant_6h_ni_apres_19h(db, factory):
    shop = factory.store()
    cash_schedule_service.run(db, now=at(3, 5, 59))
    cash_schedule_service.run(db, now=at(3, 19, 30))
    assert shop.id not in open_registers(db)


def test_traitement_idempotent(db, factory):
    shop = factory.store()
    cash_schedule_service.run(db, now=at(3, 6, 0))
    cash_schedule_service.run(db, now=at(3, 6, 1))
    cash_schedule_service.run(db, now=at(3, 12, 0))
    assert register_count(db, shop.id) == 1


def test_fermeture_automatique_a_19h_montant_compte_egal_au_theorique(db, factory, admin):
    shop = factory.store()
    cash_schedule_service.run(db, now=at(3, 6, 0))
    register = open_registers(db)[shop.id]
    cash_service.add_transaction(
        db, register, transaction_type=CashTransactionType.DEPOSIT, amount=Decimal("5000"), user_id=admin.id
    )
    db.commit()

    cash_schedule_service.run(db, now=at(3, 18, 59))
    assert shop.id in open_registers(db), "encore ouverte à 18:59"

    result = cash_schedule_service.run(db, now=at(3, 19, 0))
    db.refresh(register)
    assert register.status == CashRegisterStatus.CLOSED
    assert register.closing_amount == register.expected_amount == Decimal("5000")
    assert register.difference == Decimal("0")
    assert register.closed_automatically is True and register.closed_by is None
    assert register.closed_at == at(3, 19, 0)
    assert register.id in result.closed
    assert db.scalar(
        select(AuditLog).where(AuditLog.action == "cash.auto_close", AuditLog.entity_id == register.id)
    )


def test_le_lendemain_le_fond_de_caisse_reprend_le_montant_de_la_cloture(db, factory, admin):
    shop = factory.store()
    cash_schedule_service.run(db, now=at(3, 6, 0))
    register = open_registers(db)[shop.id]
    cash_service.add_transaction(
        db, register, transaction_type=CashTransactionType.DEPOSIT, amount=Decimal("12000"), user_id=admin.id
    )
    db.commit()
    cash_schedule_service.run(db, now=at(3, 19, 0))

    cash_schedule_service.run(db, now=at(4, 6, 0))
    tomorrow = open_registers(db)[shop.id]
    assert tomorrow.id != register.id
    assert tomorrow.opening_amount == tomorrow.expected_amount == Decimal("12000")


def test_une_cloture_manuelle_dans_la_journee_est_respectee(client, db, factory, admin_headers):
    shop = factory.store()
    cash_schedule_service.run(db, now=at(3, 6, 0))
    register = open_registers(db)[shop.id]
    response = client.post(
        f"/api/v1/cash/registers/{register.id}/close", headers=admin_headers, json={"closing_amount": 0}
    )
    assert response.status_code == 200
    assert response.json()["closed_automatically"] is False

    cash_schedule_service.run(db, now=at(3, 10, 0))
    assert shop.id not in open_registers(db), "pas de réouverture automatique le même jour"
    assert register_count(db, shop.id) == 1


def test_caisse_ouverte_a_la_main_apres_19h_fermee_le_lendemain_a_19h(db, factory, admin):
    shop = factory.store()
    late = CashRegister(
        store_id=shop.id,
        opened_by=admin.id,
        opening_amount=Decimal("0"),
        expected_amount=Decimal("0"),
        status=CashRegisterStatus.OPEN,
        opened_at=at(3, 20, 0),
    )
    db.add(late)
    db.commit()

    cash_schedule_service.run(db, now=at(3, 21, 0))
    cash_schedule_service.run(db, now=at(4, 6, 0))
    assert open_registers(db)[shop.id].id == late.id, "toujours la même caisse, pas de doublon"

    cash_schedule_service.run(db, now=at(4, 19, 0))
    db.refresh(late)
    assert late.status == CashRegisterStatus.CLOSED and late.closed_automatically


def test_rattrapage_apres_un_arret_du_serveur(db, factory):
    shop = factory.store()
    cash_schedule_service.run(db, now=at(3, 6, 0))
    yesterday = open_registers(db)[shop.id]

    # Serveur arrêté à 19:00 et à 06:00 : relancé le lendemain à 09:00.
    result = cash_schedule_service.run(db, now=at(4, 9, 0))
    db.refresh(yesterday)
    assert yesterday.status == CashRegisterStatus.CLOSED and yesterday.id in result.closed
    today = open_registers(db)[shop.id]
    assert today.id != yesterday.id and today.opened_automatically


def test_vente_en_especes_dans_une_caisse_ouverte_automatiquement(client, db, factory, admin_headers):
    product = factory.product(stock=10)
    cash_schedule_service.run(db, now=at(3, 6, 0))

    response = client.post(
        "/api/v1/sales", headers=admin_headers, json=sale_payload((product, 1), payment={"method": "CASH"})
    )

    assert response.status_code == 201, response.json()
    register = open_registers(db)[factory.central_store().id]
    db.refresh(register)
    assert register.expected_amount == Decimal(str(response.json()["total"]))


def test_horaires_publies_par_l_api(client, admin_headers):
    response = client.get("/api/v1/cash/schedule", headers=admin_headers)
    assert response.status_code == 200
    body = response.json()
    assert body["open_time"] == "06:00" and body["close_time"] == "19:00"
    assert body["timezone"] == "Indian/Antananarivo"
    assert "enabled" in body
