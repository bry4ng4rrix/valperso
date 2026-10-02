"""Factures : contenu, calculs, et fidélité historique (société, produits, prix)."""

import pytest

from app.tests.helpers import due_date, sale_payload

COMPANY = {
    "name": "Allsafe",
    "logo_url": "https://cdn.exemple.mg/allsafe/logo.png",
    "phone": "034 12 345 67",
    "email": "contact@allsafe.mg",
    "address": "Boutique H101",
    "city": "Antananarivo",
}


@pytest.fixture
def shop(factory):
    return factory.store("Magasin Analakely")


@pytest.fixture
def products(factory, shop):
    produit_a = factory.product(
        reference="A-001", name="Produit A", purchase_price="6000", selling_price="10000"
    )
    produit_b = factory.product(
        reference="B-001", name="Produit B", purchase_price="20000", selling_price="25000"
    )
    for product in (produit_a, produit_b):
        factory.add_stock(product, 10, shop)
    return produit_a, produit_b


def sell(client, headers, store, products, **fields) -> int:
    """Vend 2 x Produit A et 1 x Produit B (45 000 Ar) et renvoie l'id de la vente."""
    produit_a, produit_b = products
    payload = sale_payload((produit_a, 2), (produit_b, 1), store_id=store.id, **fields)
    return client.post("/api/v1/sales", headers=headers, json=payload).json()["id"]


def get_invoice(client, headers, sale_id) -> dict:
    return client.get(f"/api/v1/sales/{sale_id}/invoice", headers=headers).json()


def test_invoice_contains_everything(client, factory, admin, admin_headers, shop, products):
    """Exemple de la spécification : sous-total 45 000, remise 5 000, total 40 000, payé 20 000."""
    client.put("/api/v1/company", headers=admin_headers, json=COMPANY)
    sale_id = sell(
        client,
        admin_headers,
        shop,
        products,
        discount_type="FIXED",
        discount_value=5000,
        payment={"method": "CASH", "amount": 20000},
        payment_due_date=due_date(13),
    )

    invoice = get_invoice(client, admin_headers, sale_id)

    assert invoice["company"] == {  # en-tête : informations de la société
        "name": "allsafe",
        "logo_url": COMPANY["logo_url"],
        "address": "boutique h101",
        "city": "antananarivo",
        "phone": "034 12 345 67",
        "email": "contact@allsafe.mg",
    }
    assert invoice["invoice_number"].startswith("FAC-") and invoice["date"]
    assert invoice["store"]["name"] == "magasin analakely"
    assert invoice["user"]["id"] == admin.id
    customer = invoice["customer"]
    assert (customer["first_name"], customer["last_name"], customer["phone"]) == (
        "jean",
        "rakoto",
        "0341234567",
    )
    lines = [
        (line["product_reference"], line["product_name"], line["quantity"], line["unit_price"], line["total"])
        for line in invoice["lines"]
    ]
    assert lines == [("a-001", "produit a", 2, 10000.0, 20000.0), ("b-001", "produit b", 1, 25000.0, 25000.0)]
    assert (invoice["subtotal"], invoice["discount_amount"], invoice["total"]) == (45000.0, 5000.0, 40000.0)
    assert (invoice["amount_paid"], invoice["remaining_amount"]) == (20000.0, 20000.0)
    assert invoice["payment_status"] == "PARTIAL" and invoice["payment_due_date"] == due_date(13)
    assert invoice["thank_you_message"] == ["Merci pour votre achat !", "À bientôt chez allsafe."]


def test_without_discount_subtotal_equals_total(client, admin_headers, shop, products):
    invoice = get_invoice(client, admin_headers, sell(client, admin_headers, shop, products))
    assert invoice["subtotal"] == invoice["total"] == 45000.0 and invoice["discount_amount"] == 0.0
    assert invoice["payment_status"] == "PAID" and invoice["remaining_amount"] == 0.0


def test_logo_is_optional(client, factory, admin_headers, shop, products):
    factory.company(logo_url=None)
    invoice = get_invoice(client, admin_headers, sell(client, admin_headers, shop, products))
    assert invoice["company"]["logo_url"] is None


def test_thank_you_message_follows_the_company_name(client, admin_headers, shop, products):
    client.put("/api/v1/company", headers=admin_headers, json={**COMPANY, "name": "Tech Store"})
    invoice = get_invoice(client, admin_headers, sell(client, admin_headers, shop, products))
    assert invoice["thank_you_message"][1] == "À bientôt chez tech store."


def test_old_invoice_keeps_company_information_of_the_sale_date(client, admin_headers, shop, products):
    client.put("/api/v1/company", headers=admin_headers, json=COMPANY)
    old_sale_id = sell(client, admin_headers, shop, products)

    renamed = {
        **COMPANY,
        "name": "Allsafe Madagascar",
        "address": "Boutique H202",
        "city": "Antsirabe",
        "logo_url": "/media/logo-v2.png",
    }
    client.put("/api/v1/company", headers=admin_headers, json=renamed)
    new_invoice = get_invoice(client, admin_headers, sell(client, admin_headers, shop, products))
    old_invoice = get_invoice(client, admin_headers, old_sale_id)

    old_company = old_invoice["company"]
    assert (old_company["name"], old_company["address"], old_company["city"]) == (
        "allsafe",
        "boutique h101",
        "antananarivo",
    )
    assert old_company["logo_url"] == COMPANY["logo_url"]
    assert old_invoice["thank_you_message"][1] == "À bientôt chez allsafe."
    new_company = new_invoice["company"]
    assert (new_company["name"], new_company["address"], new_company["city"]) == (
        "allsafe madagascar",
        "boutique h202",
        "antsirabe",
    )
    assert new_company["logo_url"] == "/media/logo-v2.png"


def test_old_invoice_keeps_product_and_price_of_the_sale(client, admin_headers, shop, products):
    sale_id = sell(client, admin_headers, shop, products)
    produit_a = products[0]

    client.patch(
        f"/api/v1/products/{produit_a.id}",
        headers=admin_headers,
        json={"name": "Produit A v2", "reference": "A-002", "selling_price": 18000},
    )
    client.delete(f"/api/v1/products/{produit_a.id}", headers=admin_headers)

    invoice = get_invoice(client, admin_headers, sale_id)
    line = invoice["lines"][0]
    assert (line["product_reference"], line["product_name"], line["unit_price"]) == (
        "a-001",
        "produit a",
        10000.0,
    )
    assert invoice["total"] == 45000.0


def test_amounts_follow_payments_without_rewriting_history(client, admin_headers, shop, products):
    sale_id = sell(client, admin_headers, shop, products, payment=None, payment_due_date=due_date())
    client.post(
        "/api/v1/payments",
        headers=admin_headers,
        json={"sale_id": sale_id, "method": "CARD", "amount": 15000},
    )
    client.post(
        "/api/v1/payments",
        headers=admin_headers,
        json={"sale_id": sale_id, "method": "CARD", "amount": 30000},
    )

    invoice = get_invoice(client, admin_headers, sale_id)

    assert [payment["amount"] for payment in invoice["payments"]] == [15000.0, 30000.0]
    assert (invoice["amount_paid"], invoice["remaining_amount"], invoice["payment_status"]) == (
        45000.0,
        0.0,
        "PAID",
    )


def test_vendeur_reads_invoices_of_his_store_only(client, factory, admin_headers, shop, products):
    sale_id = sell(client, admin_headers, shop, products)
    own_headers = factory.headers(factory.vendeur(shop))
    other_headers = factory.headers(factory.vendeur(factory.store()))
    assert client.get(f"/api/v1/sales/{sale_id}/invoice", headers=own_headers).status_code == 200
    assert client.get(f"/api/v1/sales/{sale_id}/invoice", headers=other_headers).status_code == 403


def test_each_line_keeps_its_description(client, admin_headers, shop, products):
    """Précision saisie dans le panier (taille, couleur...) : sur la vente et sur la facture."""
    produit_a, produit_b = products
    payload = sale_payload((produit_a, 2), (produit_b, 1), store_id=shop.id)
    payload["items"][0]["description"] = "  Taille M, noir "
    sale = client.post("/api/v1/sales", headers=admin_headers, json=payload).json()

    invoice = get_invoice(client, admin_headers, sale["id"])

    assert [item["description"] for item in sale["items"]] == ["taille m, noir", None]
    assert [line["description"] for line in invoice["lines"]] == ["taille m, noir", None]
