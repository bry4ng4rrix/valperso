from decimal import Decimal
from typing import TYPE_CHECKING

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import MONEY, Base, CreatedAtMixin, TimestampMixin, UpperCaseString
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
        # Règle métier : prix de vente >= prix de stock (garantie aussi par le schéma et le service).
        sa.CheckConstraint("selling_price >= purchase_price", name="selling_price_not_below_purchase_price"),
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
    images: Mapped[list["ProductImage"]] = relationship(
        back_populates="product",
        cascade="all, delete-orphan",
        lazy="selectin",
        order_by="(ProductImage.position, ProductImage.id)",
    )

    @property
    def image_url(self) -> str | None:
        """Photo principale (la première), ou None."""
        return self.images[0].url if self.images else None


class ProductImage(CreatedAtMixin, Base):
    """Photo d'un produit. Le fichier est dans MEDIA_ROOT (servi sous /media), pas dans PostgreSQL."""

    __tablename__ = "product_images"

    id: Mapped[int] = mapped_column(primary_key=True)
    product_id: Mapped[int] = mapped_column(sa.ForeignKey("products.id", ondelete="CASCADE"), index=True)
    # Chemin relatif à MEDIA_ROOT, ex. products/3f2a....jpg (nom aléatoire, jamais celui envoyé).
    path: Mapped[str] = mapped_column(sa.String(255))
    position: Mapped[int] = mapped_column(default=0, server_default="0")

    product: Mapped[Product] = relationship(back_populates="images")

    @property
    def url(self) -> str:
        return f"/media/{self.path}"
