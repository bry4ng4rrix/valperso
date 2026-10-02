"""Données de démonstration pour tester l'application en local. NE PAS UTILISER EN PRODUCTION.

Usage : python -m app.seed_demo   (avec DEMO_PASSWORD défini dans le fichier .env)

Crée, s'ils n'existent pas déjà :
- deux ADMIN (valenciaraza, antsa) ;
- les magasins H109 (Behoririka) et C209 (La City) ;
- un vendeur par magasin (vendeur1 -> H109, vendeur2 -> C209, vendeur3 -> Stock Local) ;
- des catégories et des produits de test, approvisionnés dans le Stock Local.

Tous les comptes utilisent le mot de passe DEMO_PASSWORD. Le script est idempotent.
"""

import logging

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import SessionLocal
from app.core.permissions import RoleName
from app.core.security import hash_password
from app.models import Product, Role, Store, User
from app.repositories import category_repository, role_repository, store_repository, user_repository
from app.schemas.category import CategoryCreate
from app.schemas.product import ProductCreate
from app.schemas.stock import StockEntryCreate
from app.schemas.store import StoreCreate
from app.seed import run_seed
from app.services import category_service, product_service, stock_service, store_access, store_service

logger = logging.getLogger("seed_demo")

# (username, email, prénom, nom)
ADMINS = [
    ("valenciaraza", "valenciaraza@local.mg", "Valenciaraza", "Admin"),
    ("antsa", "antsa@local.mg", "Antsa", "Coadmin"),
]
# (nom, adresse)
STORES = [("H109", "Behoririka"), ("C209", "La City")]
# (username, email, magasin ; None = Stock Local)
SELLERS = [
    ("vendeur1", "vendeur1@local.mg", "H109"),
    ("vendeur2", "vendeur2@local.mg", "C209"),
    ("vendeur3", "vendeur3@local.mg", None),
]
CATEGORIES = ["Accessoires téléphone", "Informatique", "Électricité"]
# (référence, nom, catégorie, prix de stock, prix de vente, quantité au Stock Local)
PRODUCTS = [
    ("ACC-001", "Écouteurs Bluetooth", "Accessoires téléphone", 25000, 40000, 30),
    ("ACC-002", "Chargeur USB-C 25W", "Accessoires téléphone", 18000, 30000, 50),
    ("ACC-003", "Câble USB-C 1 m", "Accessoires téléphone", 4000, 8000, 100),
    ("ACC-004", "Power bank 10 000 mAh", "Accessoires téléphone", 45000, 70000, 4),
    ("INF-001", "Clé USB 32 Go", "Informatique", 15000, 25000, 40),
    ("INF-002", "Souris sans fil", "Informatique", 20000, 35000, 25),
    ("INF-003", "Clavier USB", "Informatique", 30000, 45000, 3),
    ("INF-004", "Carte mémoire 64 Go", "Informatique", 28000, 42000, 60),
    ("ELE-001", "Ampoule LED 9 W", "Électricité", 3500, 6000, 200),
    ("ELE-002", "Multiprise 4 prises", "Électricité", 22000, 35000, 15),
]


def _get_or_create_user(
    db: Session, role: Role, username: str, email: str, first_name: str, last_name: str, store: Store | None
) -> User:
    user = user_repository.get_by_username(db, username)
    if user is None:
        # Création directe : le mot de passe de démonstration peut être plus court que la règle de l'API.
        user = User(
            username=username,
            email=email,
            first_name=first_name,
            last_name=last_name,
            password_hash=hash_password(settings.DEMO_PASSWORD or ""),
            role=role,
            store_id=store.id if store else None,
        )
        db.add(user)
        db.commit()
        logger.info("Compte %s créé (%s)", username, role.name)
    return user


def run_demo_seed(db: Session) -> None:
    run_seed(db)  # permissions, rôles, Stock Local, société
    admin_role = role_repository.get_by_name(db, RoleName.ADMIN)
    seller_role = role_repository.get_by_name(db, RoleName.VENDEUR)

    admins = [_get_or_create_user(db, admin_role, *admin, store=None) for admin in ADMINS]
    actor = admins[0]

    stores: dict[str | None, Store] = {None: store_access.get_central_store(db)}
    for name, address in STORES:
        store = store_repository.get_by_name(db, name)
        if store is None:
            store = store_service.create_store(db, actor, StoreCreate(name=name, address=address))
            logger.info("Magasin %s créé", name)
        stores[name] = store

    for username, email, store_name in SELLERS:
        store = stores[store_name]
        _get_or_create_user(db, seller_role, username, email, username.capitalize(), "Vendeur", store)

    categories = {}
    for name in CATEGORIES:
        category = category_repository.get_by_name(db, name)
        if category is None:
            category = category_service.create_category(db, actor, CategoryCreate(name=name))
        categories[name] = category

    for reference, name, category, purchase_price, selling_price, quantity in PRODUCTS:
        if db.scalar(select(Product).where(Product.reference == reference)) is not None:
            continue
        product = product_service.create_product(
            db,
            actor,
            ProductCreate(
                reference=reference,
                name=name,
                category_id=categories[category].id,
                purchase_price=purchase_price,
                selling_price=selling_price,
            ),
        )
        entry = StockEntryCreate(product_id=product.id, quantity=quantity, reason="Stock initial (démo)")
        stock_service.record_entry(db, actor, entry)
        logger.info("Produit %s créé avec %s unités au Stock Local", reference, quantity)


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    if not settings.DEMO_PASSWORD:
        raise SystemExit("Définissez DEMO_PASSWORD dans le fichier .env avant de lancer ce script.")
    with SessionLocal() as db:
        run_demo_seed(db)
    logger.info("Données de démonstration prêtes")


if __name__ == "__main__":
    main()
