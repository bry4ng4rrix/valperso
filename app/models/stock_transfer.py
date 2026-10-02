from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, CreatedAtMixin, UpperCaseString, enum_column
from app.models.enums import TransferStatus
from app.models.product import Product
from app.models.store import Store
from app.models.user import User

# Compteur des références de transfert (TRF-2026-000001), sans doublon même en cas d'accès simultanés.
transfer_number_sequence = sa.Sequence("transfer_number_seq", metadata=Base.metadata)


class StockTransfer(CreatedAtMixin, Base):
    """Déplacement physique de stock d'un magasin vers un autre (ce n'est ni une vente ni une perte)."""

    __tablename__ = "stock_transfers"
    __table_args__ = (
        sa.CheckConstraint("source_store_id <> destination_store_id", name="different_stores"),
        sa.Index("ix_stock_transfers_created_at", "created_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    reference: Mapped[str] = mapped_column(UpperCaseString(30), unique=True)
    source_store_id: Mapped[int] = mapped_column(sa.ForeignKey("stores.id"), index=True)
    destination_store_id: Mapped[int] = mapped_column(sa.ForeignKey("stores.id"), index=True)
    created_by: Mapped[int] = mapped_column(sa.ForeignKey("users.id"))
    status: Mapped[TransferStatus] = mapped_column(enum_column(TransferStatus), index=True)
    completed_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))

    items: Mapped[list["StockTransferItem"]] = relationship(
        back_populates="transfer", cascade="all, delete-orphan", lazy="selectin", order_by="StockTransferItem.id"
    )
    source_store: Mapped[Store] = relationship(foreign_keys=[source_store_id], lazy="selectin")
    destination_store: Mapped[Store] = relationship(foreign_keys=[destination_store_id], lazy="selectin")
    creator: Mapped[User] = relationship(lazy="selectin")


class StockTransferItem(Base):
    __tablename__ = "stock_transfer_items"
    __table_args__ = (sa.CheckConstraint("quantity > 0", name="quantity_positive"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    transfer_id: Mapped[int] = mapped_column(
        sa.ForeignKey("stock_transfers.id", ondelete="CASCADE"), index=True
    )
    product_id: Mapped[int] = mapped_column(sa.ForeignKey("products.id"), index=True)
    quantity: Mapped[int]

    transfer: Mapped[StockTransfer] = relationship(back_populates="items")
    product: Mapped[Product] = relationship(lazy="selectin")
