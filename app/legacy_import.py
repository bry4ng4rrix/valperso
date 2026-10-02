"""Import des données de l'ancienne application (Django « stock ») pour une société.

Usage :
    python -m app.legacy_import --source postgresql+psycopg://user:mdp@localhost:5434/legacy_stock \\
        --owner-email valenciaraza@gmail.com --report-dir backups/import \\
        [--store-address "H109=BEHORIRIKA"] [--apply]

Sans --apply : simulation (rapport seulement, rien n'est écrit dans la base de l'application).
La base cible doit être vide de produits et de ventes (base remise à zéro puis python -m app.seed).

Règles :
- seules les données de la société du propriétaire (--owner-email) sont importées : ses magasins,
  ses co-administrateurs, les comptes de ses magasins, ses produits et ses ventes ;
- l'ancienne application dupliquait chaque produit dans chaque magasin, avec des variantes
  (taille, couleur). Les fiches de même nom, même catégorie et même prix de vente deviennent UN
  produit ; la taille, la couleur et la description sont ignorées ; le stock d'un magasin est la
  somme de ses variantes (ou la quantité de la fiche si elle n'a pas de variante) ;
- un prix d'achat supérieur au prix de vente (interdit dans l'application) est ramené au prix de
  vente : ces produits sont listés dans anomalies_prix.csv ;
- chaque compte reçoit un mot de passe provisoire (mots_de_passe.txt, lisible par son seul
  propriétaire) : les mots de passe de l'ancienne application ne sont pas repris ;
- les ventes gardent leur date, leur vendeur, leur prix réel et leur paiement. Elles ne créent pas
  de mouvement de stock : le stock importé est déjà le stock actuel.
"""

import argparse
import csv
import logging
import os
import re
import secrets
import string
import unicodedata
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import datetime
from decimal import Decimal
from pathlib import Path
from zoneinfo import ZoneInfo

from sqlalchemy import create_engine, func, select, text
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import SessionLocal
from app.core.permissions import RoleName
from app.core.security import hash_password
from app.models import (
    Customer,
    Payment,
    Product,
    Sale,
    SaleItem,
    Stock,
    Store,
    User,
    invoice_number_sequence,
)
from app.models.enums import DiscountType, PaymentMethod, PaymentStatus, SaleStatus
from app.repositories import category_repository, role_repository
from app.schemas.category import CategoryCreate
from app.schemas.product import ProductCreate
from app.schemas.stock import StockEntryCreate
from app.schemas.store import StoreCreate
from app.seed import run_seed
from app.services import (
    audit_service,
    category_service,
    company_service,
    product_service,
    stock_service,
    store_access,
    store_service,
)

logger = logging.getLogger("legacy_import")

IMPORT_REASON = "IMPORT DE L'ANCIENNE APPLICATION"
IMPORT_REFERENCE = "IMPORT"
CENTRAL_DESCRIPTION = "Magasin pour les stocks locaux"
USERNAME_PATTERN = re.compile(r"^[A-Za-z0-9._-]{3,50}$")
REFERENCE_PATTERN = re.compile(r"^[A-Za-z0-9._/-]{1,50}$")
PASSWORD_ALPHABET = "".join(c for c in string.ascii_letters + string.digits if c not in "0OolI1")


# --- Règles de fusion (fonctions pures, testées sans base) -----------------------------------------


def normalize_text(value: str | None) -> str:
    """Majuscules, espaces superflus retirés : « Robe  courte » et « ROBE COURTE » sont identiques."""
    return re.sub(r"\s+", " ", (value or "").strip()).upper()


def category_keys(categories: set[str]) -> dict[str, str]:
    """Catégorie normalisée -> catégorie retenue. Un pluriel est rattaché à son singulier s'il existe
    (CHAUSSURES -> CHAUSSURE, PARFUMS -> PARFUM)."""
    normalized = {normalize_text(c) for c in categories if normalize_text(c)}
    return {
        name: name[:-1] if name.endswith("S") and name[:-1] in normalized else name for name in normalized
    }


def clean_reference(value: str | None) -> str | None:
    """Référence compatible avec l'application (lettres, chiffres, . _ / -), sinon None."""
    text_value = unicodedata.normalize("NFKD", value or "").encode("ascii", "ignore").decode()
    text_value = re.sub(r"\s+", "-", text_value.strip())
    text_value = re.sub(r"[^A-Za-z0-9._/-]", "", text_value)[:50].upper()
    return text_value if REFERENCE_PATTERN.match(text_value) else None


def most_common(values: list, default=None):
    """Valeur la plus fréquente (la première rencontrée en cas d'égalité)."""
    filtered = [value for value in values if value not in (None, "")]
    return Counter(filtered).most_common(1)[0][0] if filtered else default


def split_full_name(full_name: str | None, fallback: str) -> tuple[str, str]:
    parts = (full_name or "").strip().split()
    if not parts:
        return fallback, ""
    return parts[0], " ".join(parts[1:])


def username_for(legacy_username: str, email: str | None, taken: set[str]) -> str:
    """Identifiant valide et unique : l'ancien s'il est valide, sinon la partie avant @ de l'email."""
    candidate = legacy_username if USERNAME_PATTERN.match(legacy_username or "") else ""
    if not candidate:
        source = (email or legacy_username or "utilisateur").split("@")[0]
        candidate = re.sub(r"[^A-Za-z0-9._-]", "", source)[:45] or "utilisateur"
        if len(candidate) < 3:
            candidate = f"{candidate}usr"
    base, number = candidate, 2
    while candidate.upper() in taken:
        candidate, number = f"{base}{number}", number + 1
    taken.add(candidate.upper())
    return candidate


def temporary_password(length: int = 10) -> str:
    return "".join(secrets.choice(PASSWORD_ALPHABET) for _ in range(length))


@dataclass
class LegacyProduct:
    id: int
    name: str
    reference: str | None
    category: str | None
    purchase_price: Decimal
    selling_price: Decimal
    store_id: int
    quantity: int  # somme des variantes, ou quantité de la fiche sans variante


@dataclass
class MergedProduct:
    key: tuple[str, str, Decimal]
    name: str
    reference: str | None
    category: str | None
    selling_price: Decimal
    purchase_price: Decimal
    price_fixed: bool
    legacy_ids: list[int]
    stock_by_store: dict[int, int] = field(default_factory=dict)


def merge_products(rows: list[LegacyProduct]) -> list[MergedProduct]:
    """Regroupe les fiches de même nom, même catégorie et même prix de vente."""
    categories = category_keys({row.category for row in rows if row.category})
    groups: dict[tuple[str, str, Decimal], list[LegacyProduct]] = defaultdict(list)
    for row in rows:
        category = categories.get(normalize_text(row.category), "")
        groups[(normalize_text(row.name), category, row.selling_price)].append(row)

    merged = []
    for key, group in sorted(groups.items(), key=lambda item: (item[0][0], item[0][1], item[0][2])):
        name, category, selling_price = key
        purchase_price = most_common([row.purchase_price for row in group], selling_price)
        price_fixed = purchase_price > selling_price
        stock: dict[int, int] = defaultdict(int)
        for row in group:
            stock[row.store_id] += max(row.quantity, 0)
        merged.append(
            MergedProduct(
                key=key,
                name=name,
                reference=most_common([clean_reference(row.reference) for row in group]),
                category=category or None,
                selling_price=selling_price,
                purchase_price=selling_price if price_fixed else purchase_price,
                price_fixed=price_fixed,
                legacy_ids=sorted(row.id for row in group),
                stock_by_store=dict(stock),
            )
        )
    return merged


# --- Lecture de l'ancienne base ------------------------------------------------------------------


@dataclass
class LegacyData:
    company_name: str
    owner_id: int
    stores: list[dict]
    users: list[dict]
    products: list[LegacyProduct]
    sales: list[dict]


def read_legacy(source_url: str, owner_email: str) -> LegacyData:
    engine = create_engine(source_url)
    with engine.connect() as connection:

        def rows(sql: str, **params) -> list[dict]:
            return [dict(row._mapping) for row in connection.execute(text(sql), params)]

        owner = rows("SELECT id FROM users_customuser WHERE lower(email) = lower(:email)", email=owner_email)
        if not owner:
            raise SystemExit(f"Aucun compte {owner_email} dans l'ancienne base.")
        owner_id = owner[0]["id"]
        company = rows("SELECT company_name FROM users_adminprofile WHERE user_id = :id", id=owner_id)
        stores = rows(
            """
            SELECT m.id, m.shop_name, m.description, m.user_id
            FROM users_magasinprofile m
            WHERE m.admin_id = :owner
               OR EXISTS (SELECT 1 FROM users_magasinprofile_admins a
                          WHERE a.magasinprofile_id = m.id AND a.customuser_id = :owner)
            ORDER BY m.id
            """,
            owner=owner_id,
        )
        store_ids = [store["id"] for store in stores]
        admin_ids = {owner_id} | {
            row["customuser_id"]
            for row in rows(
                "SELECT customuser_id FROM users_magasinprofile_admins WHERE magasinprofile_id = ANY(:ids)",
                ids=store_ids,
            )
        }
        seller_ids = {store["user_id"] for store in stores if store["user_id"]}
        users = rows(
            """
            SELECT id, username, full_name, email, phone, role, is_active
            FROM users_customuser WHERE id = ANY(:ids) ORDER BY id
            """,
            ids=sorted(admin_ids | seller_ids),
        )
        for user in users:
            user["is_admin"] = user["id"] in admin_ids
            user["store_id"] = next((s["id"] for s in stores if s["user_id"] == user["id"]), None)
        products = [
            LegacyProduct(
                id=row["id"],
                name=row["name"],
                reference=row["reference"],
                category=row["category"],
                purchase_price=Decimal(row["purchase_price"] or 0),
                selling_price=Decimal(row["shell_price"] or 0),
                store_id=row["magasin_id"],
                quantity=int(row["quantity"] or 0),
            )
            for row in rows(
                """
                SELECT p.id, p.name, p.reference, p.category, p.purchase_price, p.shell_price, p.magasin_id,
                       CASE WHEN EXISTS (SELECT 1 FROM users_productvariant v WHERE v.product_id = p.id)
                            THEN (SELECT sum(v.quantity) FROM users_productvariant v
                                  WHERE v.product_id = p.id)
                            ELSE p.initial_quantity END AS quantity
                FROM users_product p WHERE p.magasin_id = ANY(:ids) ORDER BY p.id
                """,
                ids=store_ids,
            )
        ]
        sales = rows(
            """
            SELECT id, quantity, purchase_price, sale_price, total_price, payment_amount, payment_date,
                   payment_due_date, customer_name, sold_at, magasin_id, product_id, seller_id
            FROM users_sale WHERE magasin_id = ANY(:ids) ORDER BY sold_at, id
            """,
            ids=store_ids,
        )
    engine.dispose()
    return LegacyData(
        company_name=company[0]["company_name"] if company else "",
        owner_id=owner_id,
        stores=stores,
        users=users,
        products=products,
        sales=sales,
    )


# --- Écriture dans l'application ----------------------------------------------------------------


@dataclass
class ImportReport:
    merged: list[MergedProduct]
    passwords: list[tuple[str, str, str, str]] = field(default_factory=list)  # nom, identifiant, email, mdp
    sales: int = 0
    stores: list[str] = field(default_factory=list)


def _ensure_empty_target(db: Session) -> None:
    products = db.scalar(select(func.count()).select_from(Product))
    sales = db.scalar(select(func.count()).select_from(Sale))
    if products or sales:
        raise SystemExit(
            f"La base de l'application contient déjà {products} produit(s) et {sales} vente(s). "
            "Sauvegardez-la puis remettez-la à zéro avant l'import."
        )


def _is_central(store: dict) -> bool:
    return normalize_text(store["shop_name"]) == "STOCK LOCAL"


def apply_import(
    db: Session, data: LegacyData, merged: list[MergedProduct], addresses: dict[str, str]
) -> ImportReport:
    _ensure_empty_target(db)
    run_seed(db)  # permissions, rôles, Stock Local et société (idempotent)
    report = ImportReport(merged=merged)

    # Société.
    company = company_service.get_company(db)
    if data.company_name:
        company.name = data.company_name
    db.commit()

    # Magasins : le Stock Local de l'ancienne application devient le Stock Local de l'application.
    central = store_access.get_central_store(db)
    roles = {name: role_repository.get_by_name(db, name) for name in (RoleName.ADMIN, RoleName.VENDEUR)}
    taken = {name.upper() for name in db.scalars(select(User.username))}
    emails = {email.lower() for email in db.scalars(select(User.email)) if email}

    # Comptes : d'abord les administrateurs (le propriétaire sert d'auteur des opérations).
    users: dict[int, User] = {}
    ordered = sorted(data.users, key=lambda u: (u["id"] != data.owner_id, not u["is_admin"], u["id"]))
    store_map: dict[int, Store] = {}
    for legacy in ordered:
        email = (legacy["email"] or "").strip().lower() or None
        if email in emails:
            logger.warning("Email %s déjà utilisé : compte %s importé sans email", email, legacy["username"])
            email = None
        if email:
            emails.add(email)
        first, last = split_full_name(legacy["full_name"], legacy["username"].split("@")[0])
        username = username_for(legacy["username"], legacy["email"], taken)
        password = temporary_password()
        user = User(
            first_name=first,
            last_name=last,
            username=username,
            email=email,
            phone=legacy["phone"] or None,
            password_hash=hash_password(password),
            role_id=roles[RoleName.ADMIN if legacy["is_admin"] else RoleName.VENDEUR].id,
            store_id=None,
            is_active=bool(legacy["is_active"]),
        )
        db.add(user)
        db.flush()
        users[legacy["id"]] = user
        report.passwords.append((legacy["full_name"] or username, username, email or "", password))
    db.commit()
    actor = users[data.owner_id]

    for legacy in data.stores:
        if _is_central(legacy):
            store_map[legacy["id"]] = central
            continue
        name = normalize_text(legacy["shop_name"])
        store = store_service.create_store(
            db, actor, StoreCreate(name=name, address=addresses.get(name) or None)
        )
        store_map[legacy["id"]] = store
        report.stores.append(name)

    # Affectation des vendeurs à leur magasin.
    for legacy in data.users:
        if not legacy["is_admin"] and legacy["store_id"] in store_map:
            users[legacy["id"]].store_id = store_map[legacy["store_id"]].id
    db.commit()

    # Catégories.
    categories = {}
    for name in sorted({product.category for product in merged if product.category}):
        category = category_repository.get_by_name(db, name)
        categories[name] = category or category_service.create_category(db, actor, CategoryCreate(name=name))

    # Produits, stock par magasin (entrée « import ») et lignes à 0 là où le produit était référencé.
    product_by_legacy: dict[int, Product] = {}
    for index, item in enumerate(merged, start=1):
        product = product_service.create_product(
            db,
            actor,
            ProductCreate(
                reference=item.reference or f"IMP-{index:04d}",
                name=item.name if len(item.name) >= 2 else f"{item.name} {item.category or 'PRODUIT'}",
                category_id=categories[item.category].id if item.category else None,
                purchase_price=item.purchase_price,
                selling_price=item.selling_price,
            ),
        )
        for legacy_id in item.legacy_ids:
            product_by_legacy[legacy_id] = product
        for legacy_store_id, quantity in sorted(item.stock_by_store.items()):
            store = store_map[legacy_store_id]
            if quantity > 0:
                stock_service.record_entry(
                    db,
                    actor,
                    StockEntryCreate(
                        product_id=product.id,
                        store_id=store.id,
                        quantity=quantity,
                        reason=IMPORT_REASON,
                        reference=IMPORT_REFERENCE,
                    ),
                )
            elif (
                db.scalar(select(Stock).where(Stock.product_id == product.id, Stock.store_id == store.id))
                is None
            ):
                db.add(
                    Stock(
                        product_id=product.id,
                        store_id=store.id,
                        quantity=0,
                        alert_threshold=settings.DEFAULT_ALERT_THRESHOLD,
                    )
                )
                db.commit()

    # Ventes : un client « comptoir » (l'ancienne application n'enregistrait que des libellés).
    customer = Customer(first_name="CLIENT", last_name="COMPTOIR", phone=None)
    db.add(customer)
    db.flush()
    zone = ZoneInfo(settings.TIMEZONE)
    for legacy in data.sales:
        product = product_by_legacy.get(legacy["product_id"])
        store = store_map.get(legacy["magasin_id"])
        if product is None or store is None:
            logger.warning("Vente %s ignorée : produit ou magasin introuvable", legacy["id"])
            continue
        seller = users.get(legacy["seller_id"], actor)
        sold_at: datetime = legacy["sold_at"]
        quantity = int(legacy["quantity"] or 1)
        unit_price = Decimal(legacy["sale_price"] or 0)
        total = Decimal(legacy["total_price"] or unit_price * quantity)
        paid = min(Decimal(legacy["payment_amount"] or 0), total)
        status = (
            PaymentStatus.PAID
            if paid >= total
            else (PaymentStatus.PARTIAL if paid > 0 else PaymentStatus.UNPAID)
        )
        counter = db.scalar(select(invoice_number_sequence.next_value()))
        sale = Sale(
            sale_number=f"FAC-{sold_at.astimezone(zone).year}-{counter:06d}",
            customer_id=customer.id,
            store_id=store.id,
            user_id=seller.id,
            subtotal=total,
            discount_type=DiscountType.NONE,
            discount_value=Decimal("0"),
            discount_amount=Decimal("0"),
            total=total,
            payment_status=status,
            payment_due_date=legacy["payment_due_date"] if paid < total else None,
            status=SaleStatus.COMPLETED,
            created_at=sold_at,
            updated_at=sold_at,
        )
        sale.items.append(
            SaleItem(
                product_id=product.id,
                product_reference=product.reference,
                product_name=product.name,
                quantity=quantity,
                unit_price=unit_price,
                unit_purchase_price=Decimal(legacy["purchase_price"] or product.purchase_price),
                total=total,
                created_at=sold_at,
            )
        )
        sale.company_snapshot = company_service.snapshot_for_invoice(db, store)
        db.add(sale)
        db.flush()
        if paid > 0:
            db.add(
                Payment(
                    sale_id=sale.id,
                    method=PaymentMethod.CASH,
                    amount=paid,
                    reference=IMPORT_REFERENCE,
                    created_by=seller.id,
                    created_at=legacy["payment_date"] or sold_at,
                )
            )
        report.sales += 1
    audit_service.record(
        db,
        user_id=None,
        action="legacy.import",
        entity_type="company",
        entity_id=company.id,
        new_data={
            "users": len(users),
            "stores": len(store_map),
            "products": len(merged),
            "legacy_products": sum(len(item.legacy_ids) for item in merged),
            "sales": report.sales,
        },
    )
    db.commit()
    return report


# --- Rapports -----------------------------------------------------------------------------------


def write_reports(
    report_dir: Path, data: LegacyData, merged: list[MergedProduct], report: ImportReport | None
) -> None:
    report_dir.mkdir(parents=True, exist_ok=True)
    store_names = {store["id"]: store["shop_name"] for store in data.stores}
    names_by_id = {row.id: row for row in data.products}
    with open(report_dir / "produits_fusionnes.csv", "w", newline="", encoding="utf-8") as file:
        writer = csv.writer(file, delimiter=";")
        writer.writerow(
            [
                "Produit",
                "Catégorie",
                "Prix de vente",
                "Prix d'achat",
                "Référence",
                "Stock par magasin",
                "Fiches fusionnées",
                "Noms d'origine",
            ]
        )
        for item in merged:
            writer.writerow(
                [
                    item.name,
                    item.category or "",
                    item.selling_price,
                    item.purchase_price,
                    item.reference or "(générée)",
                    ", ".join(f"{store_names[s]}: {q}" for s, q in sorted(item.stock_by_store.items())),
                    len(item.legacy_ids),
                    " | ".join(sorted({names_by_id[i].name for i in item.legacy_ids})),
                ]
            )
    with open(report_dir / "anomalies_prix.csv", "w", newline="", encoding="utf-8") as file:
        writer = csv.writer(file, delimiter=";")
        writer.writerow(
            ["Produit", "Catégorie", "Prix de vente", "Prix d'achat d'origine", "Prix d'achat importé"]
        )
        for item in merged:
            if item.price_fixed:
                original = most_common([names_by_id[i].purchase_price for i in item.legacy_ids])
                writer.writerow(
                    [item.name, item.category or "", item.selling_price, original, item.purchase_price]
                )
    if report and report.passwords:
        path = report_dir / "mots_de_passe.txt"
        with open(path, "w", encoding="utf-8") as file:
            file.write(
                "Mots de passe provisoires (à communiquer à chaque personne, puis supprimer ce fichier)\n\n"
            )
            for name, username, email, password in report.passwords:
                file.write(
                    f"{name:<20} identifiant: {username:<12} email: {email:<28} mot de passe: {password}\n"
                )
        os.chmod(path, 0o600)


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description="Import des données de l'ancienne application.")
    parser.add_argument("--source", required=True, help="URL SQLAlchemy de l'ancienne base (copie locale)")
    parser.add_argument("--owner-email", required=True, help="Email du propriétaire de la société à importer")
    parser.add_argument("--report-dir", default="backups/import", help="Dossier des rapports")
    parser.add_argument(
        "--store-address", action="append", default=[], help='Adresse d\'un magasin : "H109=BEHORIRIKA"'
    )
    parser.add_argument("--apply", action="store_true", help="Écrire dans la base (sinon : simulation)")
    args = parser.parse_args()

    addresses = {}
    for value in args.store_address:
        name, _, address = value.partition("=")
        addresses[normalize_text(name)] = address.strip()

    data = read_legacy(args.source, args.owner_email)
    merged = merge_products(data.products)
    logger.info(
        "Société %s : %d magasin(s), %d compte(s), %d fiche(s) produit -> %d produit(s), %d vente(s)",
        data.company_name,
        len(data.stores),
        len(data.users),
        len(data.products),
        len(merged),
        len(data.sales),
    )
    logger.info("Prix d'achat corrigés : %d produit(s)", sum(item.price_fixed for item in merged))

    report = None
    if args.apply:
        with SessionLocal() as db:
            report = apply_import(db, data, merged, addresses)
        logger.info("Import terminé : %d vente(s) importée(s)", report.sales)
    else:
        logger.info("Simulation : rien n'a été écrit. Relancez avec --apply pour importer.")
    write_reports(Path(args.report_dir), data, merged, report)
    logger.info("Rapports écrits dans %s", args.report_dir)


if __name__ == "__main__":
    main()
