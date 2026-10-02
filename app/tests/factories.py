"""Création rapide de données de test. Chaque méthode valide (commit) ce qu'elle crée."""

import itertools
from decimal import Decimal
from functools import cache

from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.permissions import PermissionCode, RoleName
from app.core.security import create_access_token, hash_password
from app.models import (
    COMPANY_ID,
    Category,
    CompanyInformation,
    Customer,
    Product,
    Role,
    Stock,
    Store,
    User,
)
from app.repositories import role_repository, stock_repository, store_repository

DEFAULT_PASSWORD = "Password123"


@cache
def _password_hash(password: str) -> str:
    return hash_password(password)  # bcrypt est lent : un seul calcul par mot de passe


class Factory:
    def __init__(self, db: Session) -> None:
        self.db = db
        self._sequence = itertools.count(1)

    def _save[T](self, obj: T) -> T:
        self.db.add(obj)
        self.db.commit()
        return obj

    def _next(self) -> int:
        return next(self._sequence)

    # --- Magasins et catalogue -------------------------------------------------------------------

    def central_store(self) -> Store:
        store = store_repository.get_central(self.db)
        assert store is not None
        return store

    def store(self, name: str | None = None, **fields) -> Store:
        return self._save(Store(name=name or f"Magasin {self._next()}", **fields))

    def category(self, name: str | None = None, **fields) -> Category:
        return self._save(Category(name=name or f"Catégorie {self._next()}", **fields))

    def product(
        self,
        *,
        stock: int = 0,
        store: Store | None = None,
        selling_price: str = "1000",
        purchase_price: str = "600",
        **fields,
    ) -> Product:
        """Produit avec sa ligne Stock Local (comme le service) et `stock` unités dans `store`
        (par défaut le Stock Local)."""
        number = self._next()
        central_id = self.central_store().id  # avant Product(...) : pas d'autoflush d'un produit incomplet
        product = Product(
            reference=fields.pop("reference", f"REF-{number:04d}"),
            name=fields.pop("name", f"Produit {number}"),
            selling_price=Decimal(selling_price),
            purchase_price=Decimal(purchase_price),
            **fields,
        )
        product.stocks.append(
            Stock(store_id=central_id, quantity=0, alert_threshold=settings.DEFAULT_ALERT_THRESHOLD)
        )
        self._save(product)
        if stock:
            self.add_stock(product, stock, store)
        return product

    def add_stock(self, product: Product, quantity: int, store: Store | None = None) -> Stock:
        store = store or self.central_store()
        line = stock_repository.get_line(self.db, store.id, product.id)
        if line is None:
            line = Stock(
                store_id=store.id,
                product_id=product.id,
                quantity=0,
                alert_threshold=settings.DEFAULT_ALERT_THRESHOLD,
            )
            self.db.add(line)
        line.quantity += quantity
        self.db.commit()
        return line

    def quantity(self, store: Store, product: Product) -> int:
        self.db.expire_all()
        line = stock_repository.get_line(self.db, store.id, product.id)
        return line.quantity if line else 0

    # --- Utilisateurs, rôles et clients ----------------------------------------------------------

    def role(self, name: RoleName) -> Role:
        role = role_repository.get_by_name(self.db, name)
        assert role is not None
        return role

    def set_role_permissions(self, name: RoleName, *permissions: PermissionCode) -> None:
        self.role(name).permissions = role_repository.get_permissions_by_names(
            self.db, [code.value for code in permissions]
        )
        self.db.commit()

    def grant(self, name: RoleName, *permissions: PermissionCode) -> None:
        role = self.role(name)
        role.permissions.extend(
            role_repository.get_permissions_by_names(self.db, [p.value for p in permissions])
        )
        self.db.commit()

    def user(
        self,
        role: RoleName = RoleName.VENDEUR,
        store: Store | None = None,
        *,
        password: str = DEFAULT_PASSWORD,
        **fields,
    ) -> User:
        number = self._next()
        user = User(
            first_name=fields.pop("first_name", "Prénom"),
            last_name=fields.pop("last_name", f"Nom {number}"),
            username=fields.pop("username", f"user{number}"),
            password_hash=_password_hash(password),
            role=self.role(role),
            store_id=store.id if store else None,
            **fields,
        )
        return self._save(user)

    def admin(self, **fields) -> User:
        return self.user(RoleName.ADMIN, **fields)

    def vendeur(self, store: Store | None, **fields) -> User:
        return self.user(RoleName.VENDEUR, store, **fields)

    def customer(
        self, first_name: str = "Jean", last_name: str = "Rakoto", phone: str | None = "0341234567"
    ) -> Customer:
        return self._save(Customer(first_name=first_name, last_name=last_name, phone=phone))

    @staticmethod
    def headers(user: User) -> dict[str, str]:
        return {"Authorization": f"Bearer {create_access_token(user.id)}"}

    # --- Société ---------------------------------------------------------------------------------

    def company(self, **fields) -> CompanyInformation:
        """Configure la société (ligne unique créée par le seed)."""
        company = self.db.get(CompanyInformation, COMPANY_ID)
        for field, value in fields.items():
            setattr(company, field, value)
        self.db.commit()
        return company
