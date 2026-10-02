"""Garde-fous ajoutés après la revue de code : isolation des magasins dans la gestion des utilisateurs,
annulation de transfert, révocation des jetons, historique des factures et du bénéfice, numérotation."""

import re

from app.core.permissions import PermissionCode, RoleName
from app.tests.factories import DEFAULT_PASSWORD
from app.tests.helpers import due_date, sale_payload

# --- Un non-ADMIN qui reçoit des permissions user.* reste limité à son magasin -------------------


def test_delegated_user_manager_cannot_change_his_own_store(client, factory):
    factory.grant(RoleName.VENDEUR, PermissionCode.USER_UPDATE)
    store_a, store_b = factory.store(), factory.store()
    vendeur = factory.vendeur(store_a)

    response = client.put(
        f"/api/v1/users/{vendeur.id}/store", headers=factory.headers(vendeur), json={"store_id": store_b.id}
    )

    assert response.status_code == 403


def test_delegated_user_manager_cannot_touch_users_of_another_store(client, factory):
    factory.grant(RoleName.VENDEUR, PermissionCode.USER_UPDATE)
    manager = factory.vendeur(factory.store())
    other = factory.vendeur(factory.store())

    response = client.put(
        f"/api/v1/users/{other.id}",
        headers=factory.headers(manager),
        json={"first_name": "X", "last_name": "Y", "username": "pirate", "password": "Password123"},
    )

    assert response.status_code == 403


def test_delegated_user_creator_only_creates_in_his_store(client, factory):
    factory.grant(RoleName.VENDEUR, PermissionCode.USER_CREATE)
    own_store, other_store = factory.store(), factory.store()
    headers = factory.headers(factory.vendeur(own_store))
    body = {"first_name": "A", "last_name": "B", "password": "Password123"}

    elsewhere = client.post(
        "/api/v1/users", headers=headers, json={**body, "username": "nouveau1", "store_id": other_store.id}
    )
    default = client.post("/api/v1/users", headers=headers, json={**body, "username": "nouveau2"})

    assert elsewhere.status_code == 403
    assert default.status_code == 201 and default.json()["store_id"] == own_store.id


# --- Annuler un transfert exige l'accès aux deux magasins ----------------------------------------


def test_transfer_cancel_requires_access_to_both_stores(client, factory, admin_headers):
    source, destination = factory.store(), factory.store()
    product = factory.product()
    factory.add_stock(product, 5, source)
    transfer_id = client.post(
        "/api/v1/stock-transfers",
        headers=admin_headers,
        json={
            "source_store_id": source.id,
            "destination_store_id": destination.id,
            "items": [{"product_id": product.id, "quantity": 4}],
        },
    ).json()["id"]
    factory.grant(RoleName.VENDEUR, PermissionCode.STORE_TRANSFER_CANCEL)

    response = client.post(
        f"/api/v1/stock-transfers/{transfer_id}/cancel", headers=factory.headers(factory.vendeur(source))
    )

    assert response.status_code == 403
    assert factory.quantity(destination, product) == 4


# --- Un changement de mot de passe révoque les jetons existants ----------------------------------


def test_password_change_revokes_existing_tokens(client, factory, admin_headers):
    factory.vendeur(factory.store(), username="tiana")
    tokens = client.post(
        "/api/v1/auth/login", json={"username": "tiana", "password": DEFAULT_PASSWORD}
    ).json()
    old_headers = {"Authorization": f"Bearer {tokens['access_token']}"}
    user_id = client.get("/api/v1/auth/me", headers=old_headers).json()["id"]

    client.put(
        f"/api/v1/users/{user_id}",
        headers=admin_headers,
        json={"first_name": "Tiana", "last_name": "R", "username": "tiana", "password": "NouveauMdp456"},
    )

    me = client.get("/api/v1/auth/me", headers=old_headers)
    refreshed = client.post("/api/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert me.status_code == 401 and me.json()["code"] == "TOKEN_REVOKED"
    assert refreshed.status_code == 401
    new_login = client.post("/api/v1/auth/login", json={"username": "tiana", "password": "NouveauMdp456"})
    assert new_login.status_code == 200


# --- Historique : magasin de la facture et bénéfice des ventes passées ---------------------------


def test_old_invoice_keeps_the_store_as_it_was(client, factory, admin_headers):
    store = factory.store("Magasin H109", address="Behoririka")
    product = factory.product(stock=5, store=store)
    sale_id = client.post(
        "/api/v1/sales", headers=admin_headers, json=sale_payload((product, 1), store_id=store.id)
    ).json()["id"]

    client.patch(
        f"/api/v1/stores/{store.id}", headers=admin_headers, json={"name": "H109 Bis", "address": "Ivato"}
    )

    invoice = client.get(f"/api/v1/sales/{sale_id}/invoice", headers=admin_headers).json()
    assert (invoice["store"]["name"], invoice["store"]["address"]) == ("magasin h109", "behoririka")


def test_past_profit_does_not_change_with_the_purchase_price(client, factory, admin_headers):
    product = factory.product(purchase_price="6000", selling_price="10000", stock=10)
    client.post("/api/v1/sales", headers=admin_headers, json=sale_payload((product, 2)))
    before = client.get("/api/v1/dashboard/summary", headers=admin_headers).json()["estimated_profit"]

    client.patch(f"/api/v1/products/{product.id}", headers=admin_headers, json={"purchase_price": 9000})

    after = client.get("/api/v1/dashboard/summary", headers=admin_headers).json()["estimated_profit"]
    assert before == after == 8000.0


# --- Une vente refusée ne consomme pas de numéro de facture --------------------------------------


def test_refused_sale_does_not_consume_an_invoice_number(client, factory, admin_headers):
    product = factory.product(stock=10)
    first = client.post("/api/v1/sales", headers=admin_headers, json=sale_payload((product, 1))).json()
    refused = client.post(
        "/api/v1/sales", headers=admin_headers, json=sale_payload((product, 1), payment={"method": "CASH"})
    )
    second = client.post(
        "/api/v1/sales",
        headers=admin_headers,
        json=sale_payload((product, 1), payment=None, payment_due_date=due_date()),
    ).json()

    assert refused.json()["code"] == "CASH_REGISTER_CLOSED"
    first_number = int(re.search(r"(\d+)$", first["sale_number"]).group(1))
    second_number = int(re.search(r"(\d+)$", second["sale_number"]).group(1))
    assert second_number == first_number + 1
