import sqlalchemy as sa
from sqlalchemy.ext.hybrid import hybrid_property
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin
from app.models.product import Product
from app.models.store import Store


class Stock(TimestampMixin, Base):
    """Quantité d'un produit dans un magasin. Une seule ligne par couple (produit, magasin)."""

    __tablename__ = "stocks"
    __table_args__ = (
        sa.UniqueConstraint("product_id", "store_id"),
        sa.CheckConstraint("quantity >= 0", name="quantity_not_negative"),
        sa.CheckConstraint("alert_threshold >= 0", name="alert_threshold_not_negative"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    product_id: Mapped[int] = mapped_column(sa.ForeignKey("products.id"), index=True)
    store_id: Mapped[int] = mapped_column(sa.ForeignKey("stores.id"), index=True)
    quantity: Mapped[int] = mapped_column(default=0, server_default="0")
    alert_threshold: Mapped[int]

    product: Mapped[Product] = relationship(back_populates="stocks", lazy="selectin")
    store: Mapped[Store] = relationship(back_populates="stocks", lazy="selectin")

    # États calculés (jamais stockés). Ils fonctionnent en Python et dans les requêtes SQL :
    # `stock.low_stock` -> bool, `select(Stock).where(Stock.low_stock)` -> filtre SQL.
    @hybrid_property
    def out_of_stock(self) -> bool:
        return self.quantity == 0

    @hybrid_property
    def low_stock(self) -> bool:
        """Stock faible : il reste des unités, mais pas plus que le seuil d'alerte."""
        return (self.quantity > 0) & (self.quantity <= self.alert_threshold)
