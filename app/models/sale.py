from datetime import date
from decimal import Decimal
from typing import TYPE_CHECKING

import sqlalchemy as sa
from sqlalchemy.ext.hybrid import hybrid_property
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import MONEY, Base, CreatedAtMixin, TimestampMixin, UpperCaseString, enum_column
from app.models.customer import Customer
from app.models.enums import DiscountType, PaymentStatus, SaleStatus
from app.models.store import Store
from app.models.user import User

if TYPE_CHECKING:
    from app.models.payment import Payment

# Compteur des numéros de facture (FAC-2026-000125), sans doublon même en cas de ventes simultanées.
invoice_number_sequence = sa.Sequence("invoice_number_seq", metadata=Base.metadata)


class Sale(TimestampMixin, Base):
    """Vente. `sale_number` est le numéro de facture.

    `amount_paid` (somme des paiements) est calculé par PostgreSQL : il est défini dans
    models/payment.py, après la classe Payment. Il n'est jamais stocké ni reçu du frontend.
    """

    __tablename__ = "sales"
    __table_args__ = (
        sa.CheckConstraint("subtotal >= 0", name="subtotal_not_negative"),
        sa.CheckConstraint("discount_value >= 0", name="discount_value_not_negative"),
        sa.CheckConstraint(
            "discount_amount >= 0 AND discount_amount <= subtotal", name="discount_amount_valid"
        ),
        sa.CheckConstraint("total >= 0", name="total_not_negative"),
        sa.Index("ix_sales_created_at", "created_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    sale_number: Mapped[str] = mapped_column(UpperCaseString(30), unique=True)
    customer_id: Mapped[int] = mapped_column(sa.ForeignKey("customers.id"), index=True)
    store_id: Mapped[int] = mapped_column(sa.ForeignKey("stores.id"), index=True)
    # Toujours l'utilisateur connecté (lu dans le JWT), jamais une valeur envoyée par le frontend.
    user_id: Mapped[int] = mapped_column(sa.ForeignKey("users.id"), index=True)
    subtotal: Mapped[Decimal] = mapped_column(MONEY)
    discount_type: Mapped[DiscountType] = mapped_column(
        enum_column(DiscountType), default=DiscountType.NONE, server_default=DiscountType.NONE.value
    )
    discount_value: Mapped[Decimal] = mapped_column(MONEY, default=Decimal("0"), server_default="0")
    discount_amount: Mapped[Decimal] = mapped_column(MONEY, default=Decimal("0"), server_default="0")
    total: Mapped[Decimal] = mapped_column(MONEY)
    payment_status: Mapped[PaymentStatus] = mapped_column(enum_column(PaymentStatus), index=True)
    # Date limite de paiement du reste dû (uniquement pour une vente avec avance ou à crédit).
    payment_due_date: Mapped[date | None]
    status: Mapped[SaleStatus] = mapped_column(enum_column(SaleStatus), index=True)

    customer: Mapped[Customer] = relationship(back_populates="sales", lazy="selectin")
    store: Mapped[Store] = relationship(lazy="selectin")
    user: Mapped[User] = relationship(lazy="selectin")
    items: Mapped[list["SaleItem"]] = relationship(
        back_populates="sale", cascade="all, delete-orphan", order_by="SaleItem.id"
    )
    payments: Mapped[list["Payment"]] = relationship(back_populates="sale", order_by="Payment.id")

    @hybrid_property
    def remaining_amount(self) -> Decimal:
        """Reste à payer = total - montant payé. Utilisable en Python et dans les requêtes SQL."""
        return self.total - self.amount_paid


class SaleItem(CreatedAtMixin, Base):
    """Ligne de vente. Référence, nom et prix du produit sont copiés au moment de la vente :
    la facture reste exacte même si le produit est modifié ensuite."""

    __tablename__ = "sale_items"
    __table_args__ = (
        sa.CheckConstraint("quantity > 0", name="quantity_positive"),
        sa.CheckConstraint("unit_price >= 0", name="unit_price_not_negative"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    sale_id: Mapped[int] = mapped_column(sa.ForeignKey("sales.id", ondelete="CASCADE"), index=True)
    product_id: Mapped[int] = mapped_column(sa.ForeignKey("products.id"), index=True)
    product_reference: Mapped[str] = mapped_column(UpperCaseString(50))
    product_name: Mapped[str] = mapped_column(UpperCaseString(200))
    quantity: Mapped[int]
    unit_price: Mapped[Decimal] = mapped_column(MONEY)
    total: Mapped[Decimal] = mapped_column(MONEY)

    sale: Mapped[Sale] = relationship(back_populates="items")
