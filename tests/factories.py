"""Création rapide de données de test. Chaque méthode valide (commit) ce qu'elle crée."""

import itertools
from decimal import Decimal
from functools import cache

from sqlalchemy.orm import Session

from app.core.permissions import PermissionCode, RoleName
from app.core.security import create_access_token, hash_password
from app.models import CashRegister, Category, Product, Role, Store, StoreStock, User
from app.models.enums import CashRegisterStatus
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

    def default_store(self) -> Store:
        store = store_repository.get_default(self.db)
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
        """Produit avec `stock` unités dans `store` (par défaut le STOCK LOCAL)."""
        number = self._next()
        product = Product(
            reference=fields.pop("reference", f"REF-{number:04d}"),
            name=fields.pop("name", f"Produit {number}"),
            selling_price=Decimal(selling_price),
            purchase_price=Decimal(purchase_price),
            stock=0,
            **fields,
        )
        self._save(product)
        if stock:
            self.add_stock(product, stock, store)
        return product

    def add_stock(self, product: Product, quantity: int, store: Store | None = None) -> None:
        store = store or self.default_store()
        line = stock_repository.get_line(self.db, store.id, product.id)
        if line is None:
            line = StoreStock(store_id=store.id, product_id=product.id, quantity=0)
            self.db.add(line)
        line.quantity += quantity
        product.stock += quantity
        self.db.commit()

    def store_quantity(self, store: Store, product: Product) -> int:
        line = stock_repository.get_line(self.db, store.id, product.id)
        return line.quantity if line else 0

    # --- Utilisateurs et rôles -------------------------------------------------------------------

    def role(self, *permissions: PermissionCode, name: str | None = None) -> Role:
        role = Role(
            name=name or f"ROLE_{self._next()}",
            permissions=role_repository.get_permissions_by_names(self.db, [p.value for p in permissions]),
        )
        return self._save(role)

    def user(
        self,
        role: RoleName | Role = RoleName.VENDEUR,
        store: Store | None = None,
        *,
        password: str = DEFAULT_PASSWORD,
        **fields,
    ) -> User:
        if isinstance(role, RoleName):
            role = role_repository.get_by_name(self.db, role.value)
        number = self._next()
        user = User(
            first_name=fields.pop("first_name", "Prénom"),
            last_name=fields.pop("last_name", f"Nom {number}"),
            username=fields.pop("username", f"user{number}"),
            password_hash=_password_hash(password),
            role=role,
            store_id=store.id if store else None,
            **fields,
        )
        return self._save(user)

    def admin(self) -> User:
        return self.user(RoleName.ADMIN)

    @staticmethod
    def headers(user: User) -> dict[str, str]:
        return {"Authorization": f"Bearer {create_access_token(user.id)}"}

    # --- Caisse ----------------------------------------------------------------------------------

    def open_register(self, store: Store, user: User, opening_amount: str = "0") -> CashRegister:
        amount = Decimal(opening_amount)
        register = CashRegister(
            store_id=store.id,
            opened_by=user.id,
            opening_amount=amount,
            expected_amount=amount,
            status=CashRegisterStatus.OPEN,
        )
        return self._save(register)
