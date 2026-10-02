import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, CreatedAtMixin, UpperCaseString, enum_column
from app.models.enums import StockMovementType
from app.models.product import Product
from app.models.store import Store
from app.models.user import User


class StockMovement(CreatedAtMixin, Base):
    """Historique de toute variation de stock d'un produit dans un magasin.

    `quantity` est signée : positive pour une entrée en stock, négative pour une sortie.
    """

    __tablename__ = "stock_movements"
    __table_args__ = (
        sa.CheckConstraint("quantity <> 0", name="quantity_not_zero"),
        sa.Index("ix_stock_movements_created_at", "created_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    product_id: Mapped[int] = mapped_column(sa.ForeignKey("products.id"), index=True)
    store_id: Mapped[int] = mapped_column(sa.ForeignKey("stores.id"), index=True)
    user_id: Mapped[int] = mapped_column(sa.ForeignKey("users.id"), index=True)
    type: Mapped[StockMovementType] = mapped_column(enum_column(StockMovementType))
    quantity: Mapped[int]
    reason: Mapped[str | None] = mapped_column(UpperCaseString(255))
    # Document à l'origine du mouvement : n° de facture, de transfert, de bon de livraison...
    reference: Mapped[str | None] = mapped_column(UpperCaseString(100), index=True)

    product: Mapped[Product] = relationship(lazy="selectin")
    store: Mapped[Store] = relationship(lazy="selectin")
    user: Mapped[User] = relationship(lazy="selectin")
