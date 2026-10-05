"""WebSocket temps réel : authentification, changements annoncés, isolation des magasins.

Les messages arrivent dans l'ordre : pour vérifier qu'un changement n'a PAS été envoyé, on fait
ensuite un changement visible par tous (un produit) et on vérifie que c'est le premier reçu.
"""

from contextlib import contextmanager

import pytest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from app.core.security import create_access_token
from app.models import Category
from app.tests.helpers import sale_payload

WS = "/api/v1/ws"


@contextmanager
def connect(client: TestClient, user):
    with client.websocket_connect(f"{WS}?token={create_access_token(user.id, user.token_version)}") as ws:
        assert ws.receive_json() == {"type": "ready"}  # abonné : aucun changement suivant ne sera manqué
        yield ws


def entities(message: dict) -> set[tuple[str, str]]:
    assert message["type"] == "changes"
    return {(change["entity"], change["action"]) for change in message["changes"]}


def test_connection_requires_a_valid_token(client, factory):
    for url in (WS, f"{WS}?token=invalide"):
        with client.websocket_connect(url) as ws, pytest.raises(WebSocketDisconnect) as closed:
            ws.receive_json()
        assert closed.value.code == 4401


def test_revoked_token_is_refused(client, factory, db):
    user = factory.admin()
    token = create_access_token(user.id, user.token_version)
    user.token_version += 1  # mot de passe changé
    db.commit()

    with client.websocket_connect(f"{WS}?token={token}") as ws, pytest.raises(WebSocketDisconnect) as closed:
        ws.receive_json()
    assert closed.value.code == 4401
    assert closed.value.reason == "TOKEN_REVOKED"


def test_product_created_and_deleted_are_announced_with_author(client, factory, admin, admin_headers):
    category = factory.category()
    with connect(client, admin) as ws:
        created = client.post(
            "/api/v1/products",
            headers=admin_headers,
            json={
                "reference": "RT-1",
                "name": "robe rouge",
                "category_id": category.id,
                "purchase_price": 10000,
                "selling_price": 15000,
            },
        )
        assert created.status_code == 201, created.text
        message = ws.receive_json()
        product = next(c for c in message["changes"] if c["entity"] == "product")
        assert product == {
            "entity": "product",
            "action": "created",
            "id": created.json()["id"],
            "actor_id": admin.id,
            "label": "ROBE ROUGE",
        }
        assert ("audit", "created") in entities(message)  # l'ADMIN voit aussi le journal d'audit

        client.delete(f"/api/v1/products/{created.json()['id']}", headers=admin_headers)
        assert ("product", "deleted") in entities(ws.receive_json())


def test_seller_only_receives_changes_of_his_store(client, factory, admin_headers):
    store_a, store_b = factory.store(), factory.store()
    seller_a = factory.vendeur(store_a)
    product = factory.product()
    factory.add_stock(product, 10, store_a)
    factory.add_stock(product, 10, store_b)

    customer = factory.customer()

    with connect(client, seller_a) as ws:
        sold_b = client.post(
            "/api/v1/sales",
            headers=admin_headers,
            json=sale_payload((product, 1), customer=customer, store_id=store_b.id),
        )
        assert sold_b.status_code == 201, sold_b.text
        factory.product()  # visible par tous (son stock est au Stock Local) : premier message reçu
        assert entities(ws.receive_json()) == {("product", "created")}

        sold_a = client.post(
            "/api/v1/sales",
            headers=admin_headers,
            json=sale_payload((product, 2), customer=customer, store_id=store_a.id),
        )
        assert sold_a.status_code == 201, sold_a.text
        message = ws.receive_json()
        assert {("sale", "created"), ("stock", "updated"), ("movement", "created")} <= entities(message)
        assert ("audit", "created") not in entities(message)  # journal réservé aux ADMIN
        sale = next(c for c in message["changes"] if c["entity"] == "sale")
        assert sale["label"] == sold_a.json()["sale_number"]


def test_messages_only_reach_conversation_members(client, factory):
    alice, bob, carol = factory.admin(), factory.admin(), factory.admin()
    conversation = client.post(
        "/api/v1/chat/conversations",
        headers=factory.headers(alice),
        json={"type": "PRIVATE", "member_ids": [bob.id]},
    ).json()

    with connect(client, bob) as bob_ws, connect(client, carol) as carol_ws:
        client.post(
            f"/api/v1/chat/conversations/{conversation['id']}/messages",
            headers=factory.headers(alice),
            json={"content": "Bonjour Bob"},
        )
        received = bob_ws.receive_json()
        assert ("message", "created") in entities(received)
        assert next(c for c in received["changes"] if c["entity"] == "message")["id"] == conversation["id"]

        factory.category()
        assert entities(carol_ws.receive_json()) == {("category", "created")}


def test_rolled_back_changes_are_never_announced(client, factory, admin, db):
    with connect(client, admin) as ws:
        db.add(Category(name="jamais validée"))
        db.flush()
        db.rollback()
        factory.store()
        assert entities(ws.receive_json()) == {("store", "created")}


def test_user_change_closes_the_connection_to_reload_rights(client, factory, db):
    seller = factory.vendeur(factory.store())
    with connect(client, seller) as ws:
        seller.store_id = factory.store().id
        db.commit()
        changes = []
        with pytest.raises(WebSocketDisconnect) as closed:
            while True:
                changes.append(ws.receive_json())
        assert closed.value.code == 4000
        assert any(("user", "updated") in entities(message) for message in changes)
