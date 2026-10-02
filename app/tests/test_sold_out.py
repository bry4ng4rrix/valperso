"""Produit épuisé : retiré du stock du magasin, conservé dans la base et dans les historiques."""

from sqlalchemy import select

from app.models import Sale, StockMovement
from app.repositories import stock_repository
from app.tests.helpers import sale_payload


def test_vente_de_tout_le_stock_retire_le_produit_du_magasin(client, factory, admin_headers, db):
    product = factory.product(name="Produit A", reference="PA-1", stock=10, selling_price="5000")
    central = factory.central_store()

    response = client.post("/api/v1/sales", headers=admin_headers, json=sale_payload((product, 10)))

    assert response.status_code == 201, response.json()
    # Plus de ligne « épuisé » dans le magasin...
    assert stock_repository.get_line(db, central.id, product.id) is None
    stock = client.get("/api/v1/stock", headers=admin_headers, params={"store_id": central.id}).json()
    assert product.id not in [line["product"]["id"] for line in stock["items"]]
    # ... mais le produit reste dans la base (catalogue) ...
    assert client.get(f"/api/v1/products/{product.id}", headers=admin_headers).status_code == 200
    # ... et l'historique des ventes garde son nom, sa référence et son prix.
    sale = db.scalar(select(Sale).where(Sale.id == response.json()["id"]))
    item = sale.items[0]
    assert (item.product_name, item.product_reference, item.unit_price) == ("PRODUIT A", "PA-1", 5000)
    history = client.get("/api/v1/sales/history", headers=admin_headers).json()["items"]
    assert history[0]["sale_number"] == sale.sale_number
    movement = db.scalar(
        select(StockMovement).where(StockMovement.product_id == product.id).order_by(StockMovement.id.desc())
    )
    assert movement.quantity == -10


def test_vente_partielle_garde_la_ligne(client, factory, admin_headers, db):
    product = factory.product(stock=10)
    client.post("/api/v1/sales", headers=admin_headers, json=sale_payload((product, 4)))
    assert factory.quantity(factory.central_store(), product) == 6
    assert stock_repository.get_line(db, factory.central_store().id, product.id) is not None


def test_annulation_remet_le_produit_en_stock(client, factory, admin_headers, db):
    product = factory.product(stock=3)
    sale_id = client.post("/api/v1/sales", headers=admin_headers, json=sale_payload((product, 3))).json()[
        "id"
    ]
    assert stock_repository.get_line(db, factory.central_store().id, product.id) is None

    response = client.post(
        f"/api/v1/sales/{sale_id}/cancel", headers=admin_headers, json={"reason": "Erreur de saisie"}
    )

    assert response.status_code == 200, response.json()
    assert factory.quantity(factory.central_store(), product) == 3


def test_nouvelle_entree_recree_la_ligne(client, factory, admin_headers, db):
    product = factory.product(stock=2)
    client.post("/api/v1/stock/exit", headers=admin_headers, json={"product_id": product.id, "quantity": 2})
    assert stock_repository.get_line(db, factory.central_store().id, product.id) is None

    client.post("/api/v1/stock/entry", headers=admin_headers, json={"product_id": product.id, "quantity": 5})
    assert factory.quantity(factory.central_store(), product) == 5
