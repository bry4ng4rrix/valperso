from decimal import Decimal
from typing import TYPE_CHECKING

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import MONEY, Base, TimestampMixin, UpperCaseString
from app.models.category import Category

if TYPE_CHECKING:
    from app.models.stock import Stock


class Product(TimestampMixin, Base):
    """Produit du catalogue.

    Ni la référence ni le nom ne sont uniques : seul `id` identifie un produit.
    Le produit n'a pas de champ stock : les quantités sont dans la table `stocks` (une ligne par magasin).
    """

    __tablename__ = "products"
    __table_args__ = (
        sa.CheckConstraint("purchase_price >= 0", name="purchase_price_not_negative"),
        sa.CheckConstraint("selling_price >= 0", name="selling_price_not_negative"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    reference: Mapped[str] = mapped_column(UpperCaseString(50), index=True)
    name: Mapped[str] = mapped_column(UpperCaseString(200), index=True)
    category_id: Mapped[int | None] = mapped_column(sa.ForeignKey("categories.id"), index=True)
    purchase_price: Mapped[Decimal] = mapped_column(MONEY)
    selling_price: Mapped[Decimal] = mapped_column(MONEY)
    is_active: Mapped[bool] = mapped_column(default=True, server_default=sa.true())

    category: Mapped[Category | None] = relationship(back_populates="products", lazy="selectin")
    stocks: Mapped[list["Stock"]] = relationship(back_populates="product")
