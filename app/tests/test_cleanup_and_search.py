"""Nettoyage des lignes à 0 du Stock Local et recherche de produits (nom, référence, catégorie, prix)."""

from decimal import Decimal

from sqlalchemy import select

from app.cleanup_stock import moved_out_lines, remove_lines, remove_moved_out_lines, sold_out_lines
from app.models import AuditLog
from app.repositories import product_repository, stock_repository


def test_nettoyage_retire_seulement_les_produits_deplaces(db, factory):
    central = factory.central_store()
    shop = factory.store()
    moved = factory.product(stock=5, store=shop)  # 0 au Stock Local, 5 en magasin : déplacé
    sold_out = factory.product(stock=0)  # 0 partout : vraie rupture
    in_stock = factory.product(stock=3)

    assert [line.product_id for line in moved_out_lines(db, central.id)] == [moved.id]
    assert remove_moved_out_lines(db, central.id) == 1

    assert stock_repository.get_line(db, central.id, moved.id) is None
    assert stock_repository.get_line(db, central.id, sold_out.id).quantity == 0
    assert stock_repository.get_line(db, central.id, in_stock.id).quantity == 3
    assert factory.quantity(shop, moved) == 5
    assert db.scalar(select(AuditLog).where(AuditLog.action == "stock.cleanup_moved"))
    assert remove_moved_out_lines(db, central.id) == 0, "idempotent"


def test_nettoyage_de_tous_les_produits_epuises(db, factory):
    shop = factory.store()
    sold_out = factory.product(stock=0)
    elsewhere = factory.product(stock=0, store=shop)
    factory.product(stock=4)
    assert {line.product_id for line in sold_out_lines(db)} >= {sold_out.id, elsewhere.id}
    assert remove_lines(db, sold_out_lines(db), None) >= 2
    assert sold_out_lines(db) == []
    assert factory.quantity(shop, elsewhere) == 0


def test_lecture_des_prix_saisis():
    assert product_repository.parse_price("200000") == Decimal("200000")
    assert product_repository.parse_price("200 000 Ar") == Decimal("200000")
    assert product_repository.parse_price("1500,50") == Decimal("1500.50")
    assert product_repository.parse_price("abaya") is None
    assert product_repository.parse_price("AB-200") is None


def test_recherche_par_nom_reference_categorie_et_prix(client, factory, admin_headers):
    category = factory.category(name="Chaussure")
    shoe = factory.product(
        name="Talon",
        reference="CH-100",
        category=category,
        selling_price="100000",
        purchase_price="90000",
        stock=2,
    )
    dress = factory.product(
        name="Robe courte", reference="RB-70", selling_price="70000", purchase_price="70000", stock=1
    )

    def found(term: str, path: str = "/api/v1/products") -> set[int]:
        response = client.get(path, headers=admin_headers, params={"search": term})
        assert response.status_code == 200, response.json()
        return {
            item["product"]["id"] if "product" in item else item["id"] for item in response.json()["items"]
        }

    assert found("talon") == {shoe.id}
    assert found("ch-100") == {shoe.id}
    assert found("chauss") == {shoe.id}, "catégorie"
    assert found("100 000") == {shoe.id}, "prix de vente"
    assert found("90000") == {shoe.id}, "prix d'achat"
    assert found("70000") == {dress.id}
    # Même recherche dans la liste du stock (vue par magasin).
    assert found("chaussure", "/api/v1/stock") == {shoe.id}
    assert found("70 000 Ar", "/api/v1/stock") == {dress.id}
