"""Import des données de l'ancienne application : règles de fusion et écriture."""

from datetime import UTC, datetime
from decimal import Decimal

import pytest
from sqlalchemy import func, select

from app.core.security import verify_password
from app.legacy_import import (
    LegacyData,
    LegacyProduct,
    apply_import,
    category_keys,
    clean_reference,
    merge_products,
    normalize_text,
    username_for,
)
from app.models import AuditLog, Product, Sale, Stock, StockMovement, Store, User
from app.models.enums import PaymentStatus


def row(id_, name, category, price, store, quantity, purchase=None, reference="REF-1"):
    return LegacyProduct(
        id=id_,
        name=name,
        reference=reference,
        category=category,
        purchase_price=Decimal(purchase if purchase is not None else price),
        selling_price=Decimal(price),
        store_id=store,
        quantity=quantity,
    )


def test_normalisation_des_noms_et_categories():
    assert normalize_text("  Robe   courte ") == "ROBE COURTE"
    keys = category_keys({"Chaussure", "Chaussures", "Parfums", "Sac"})
    assert keys["CHAUSSURES"] == "CHAUSSURE"
    assert keys["PARFUMS"] == "PARFUMS", "pas de singulier existant : inchangé"
    assert keys["SAC"] == "SAC"


def test_references_rendues_compatibles():
    assert clean_reference("ab-200") == "AB-200"
    assert clean_reference("TS 45 é") == "TS-45-E"
    assert clean_reference("   ") is None


def test_fusion_meme_nom_categorie_prix_tailles_et_couleurs_ignorees():
    merged = merge_products(
        [
            row(1, "ACOEUR", "Tee shirt", "45000", store=1, quantity=8),
            row(2, "Acoeur", "Tee shirt", "45000", store=16, quantity=12),
            row(3, "ACOEUR", "Tee shirt", "45000", store=15, quantity=1),
            row(4, "ACOEUR", "Tee shirt", "50000", store=1, quantity=2),  # autre prix : autre produit
            row(5, "Chaussure enfant", "Chaussures", "175000", store=1, quantity=3),
            row(6, "CHAUSSURE ENFANT", "Chaussure", "175000", store=16, quantity=4),
        ]
    )
    assert len(merged) == 3
    acoeur = next(item for item in merged if item.key == ("ACOEUR", "TEE SHIRT", Decimal("45000")))
    assert acoeur.legacy_ids == [1, 2, 3]
    assert acoeur.stock_by_store == {1: 8, 16: 12, 15: 1}
    shoes = next(item for item in merged if item.name == "CHAUSSURE ENFANT")
    assert shoes.category == "CHAUSSURE" and shoes.stock_by_store == {1: 3, 16: 4}


def test_prix_d_achat_superieur_ramene_au_prix_de_vente():
    (item,) = merge_products(
        [row(1, "Parure de lit", "Autre", "40000", store=1, quantity=1, purchase="400000")]
    )
    assert item.price_fixed and item.purchase_price == item.selling_price == Decimal("40000")


def test_identifiants_valides_et_uniques():
    taken = {"ADMIN"}
    assert username_for("Valencia", "valenciaraza@gmail.com", taken) == "Valencia"
    assert username_for("Fleur@valheri.mg", "Fleur@valheri.mg", taken) == "Fleur"
    assert username_for("fleur@autre.mg", "fleur@autre.mg", taken) == "fleur2"


@pytest.fixture
def legacy_data() -> LegacyData:
    sold_at = datetime(2026, 9, 5, 9, 30, tzinfo=UTC)
    return LegacyData(
        company_name="Valheri Wear",
        owner_id=46,
        stores=[
            {
                "id": 1,
                "shop_name": "Stock Local",
                "description": "Magasin pour les stocks locaux",
                "user_id": None,
            },
            {"id": 16, "shop_name": "H109", "description": "", "user_id": 58},
        ],
        users=[
            {
                "id": 46,
                "username": "Valencia",
                "full_name": "Valheri Wear",
                "email": "valencia@test.mg",
                "phone": "",
                "role": "admin",
                "is_active": True,
                "is_admin": True,
                "store_id": None,
            },
            {
                "id": 58,
                "username": "Sitraka@test.mg",
                "full_name": "Sitraka 1",
                "email": "Sitraka@test.mg",
                "phone": "",
                "role": "magasin",
                "is_active": True,
                "is_admin": False,
                "store_id": 16,
            },
        ],
        products=[
            row(10, "ACOEUR", "Tee shirt", "45000", store=1, quantity=8, reference="TS-45"),
            row(11, "ACOEUR", "Tee shirt", "45000", store=16, quantity=0, reference="TS-45"),
            row(12, "Robe courte", "Robe", "70000", store=16, quantity=2, purchase="80000", reference="RC"),
        ],
        sales=[
            {
                "id": 1,
                "quantity": 1,
                "purchase_price": Decimal("45000"),
                "sale_price": Decimal("40000"),
                "total_price": Decimal("40000"),
                "payment_amount": Decimal("40000"),
                "payment_date": None,
                "payment_due_date": None,
                "customer_name": "Vente H109",
                "sold_at": sold_at,
                "magasin_id": 16,
                "product_id": 11,
                "seller_id": 58,
            },
        ],
    )


def test_import_complet(db, legacy_data):
    merged = merge_products(legacy_data.products)
    report = apply_import(db, legacy_data, merged, {"H109": "BEHORIRIKA"})

    # Comptes avec mot de passe provisoire, vendeur affecté à son magasin.
    owner = db.scalar(select(User).where(User.username == "VALENCIA"))
    seller = db.scalar(select(User).where(User.email == "sitraka@test.mg"))
    assert owner.role.name == "ADMIN" and owner.store_id is None
    assert seller.role.name == "VENDEUR" and seller.store.name == "H109"
    passwords = {username: password for _, username, _, password in report.passwords}
    assert verify_password(passwords["Valencia"], owner.password_hash)

    # Magasins : Stock Local réutilisé, H109 créé avec son adresse.
    h109 = db.scalar(select(Store).where(Store.name == "H109"))
    assert h109.address == "BEHORIRIKA"

    # Produits fusionnés : ACOEUR une seule fois, stock 8 au Stock Local et ligne à 0 dans H109.
    acoeur = db.scalar(select(Product).where(Product.name == "ACOEUR"))
    stocks = {
        stock.store.name: stock.quantity
        for stock in db.scalars(select(Stock).where(Stock.product_id == acoeur.id))
    }
    assert stocks == {"STOCK LOCAL": 8, "H109": 0}
    assert db.scalar(select(func.count()).select_from(Product)) == 2
    robe = db.scalar(select(Product).where(Product.name == "ROBE COURTE"))
    assert robe.purchase_price == robe.selling_price == Decimal("70000")
    movement = db.scalar(select(StockMovement).where(StockMovement.product_id == acoeur.id))
    assert movement.reason == "IMPORT DE L'ANCIENNE APPLICATION" and movement.quantity == 8

    # Vente : date, vendeur, prix réel et paiement conservés.
    sale = db.scalar(select(Sale))
    assert sale.sale_number.startswith("FAC-2026-")
    assert sale.created_at == datetime(2026, 9, 5, 9, 30, tzinfo=UTC)
    assert sale.user_id == seller.id and sale.store_id == h109.id
    assert sale.total == Decimal("40000") and sale.amount_paid == Decimal("40000")
    assert sale.payment_status == PaymentStatus.PAID
    assert sale.items[0].product_id == acoeur.id
    assert sale.company_snapshot.company_name == "VALHERI WEAR"

    assert db.scalar(select(AuditLog).where(AuditLog.action == "legacy.import"))


def test_import_refuse_une_base_deja_remplie(db, factory, legacy_data):
    factory.product()
    with pytest.raises(SystemExit):
        apply_import(db, legacy_data, merge_products(legacy_data.products), {})
