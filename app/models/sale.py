from dataclasses import dataclass
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
from app.utils.dates import local_today

if TYPE_CHECKING:
    from app.models.company import InvoiceCompanySnapshot
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
    # Prochaine échéance non payée du reste dû (vente avec avance ou à crédit) : voir `installments`.
    payment_due_date: Mapped[date | None]
    status: Mapped[SaleStatus] = mapped_column(enum_column(SaleStatus), index=True)

    customer: Mapped[Customer] = relationship(back_populates="sales", lazy="selectin")
    store: Mapped[Store] = relationship(lazy="selectin")
    user: Mapped[User] = relationship(lazy="selectin")
    items: Mapped[list["SaleItem"]] = relationship(
        back_populates="sale", cascade="all, delete-orphan", order_by="SaleItem.id"
    )
    payments: Mapped[list["Payment"]] = relationship(back_populates="sale", order_by="Payment.id")
    # Échéancier du reste à payer : dates et montants prévus des remboursements.
    installments: Mapped[list["SaleInstallment"]] = relationship(
        back_populates="sale",
        cascade="all, delete-orphan",
        order_by="(SaleInstallment.due_date, SaleInstallment.id)",
    )
    # Informations de la société figées au moment de la vente (en-tête de la facture).
    company_snapshot: Mapped["InvoiceCompanySnapshot"] = relationship(
        back_populates="sale", cascade="all, delete-orphan"
    )

    @hybrid_property
    def remaining_amount(self) -> Decimal:
        """Reste à payer = total - montant payé. Utilisable en Python et dans les requêtes SQL."""
        return self.total - self.amount_paid

    @property
    def installment_schedule(self) -> list["InstallmentState"]:
        """Échéancier avec ce qui reste dû sur chaque échéance.

        Les échéances couvrent le reste à payer après l'avance ; les paiements reçus ensuite
        les soldent dans l'ordre des dates. Ce qui reste dû se répartit donc sur les dernières.
        """
        remaining = max(self.remaining_amount, Decimal("0"))
        later = sum((installment.amount for installment in self.installments), Decimal("0"))
        states = []
        for installment in self.installments:
            later -= installment.amount
            due = min(max(remaining - later, Decimal("0")), installment.amount)
            states.append(InstallmentState(installment.due_date, installment.amount, due))
        return states

    @property
    def next_installment_date(self) -> date | None:
        """Date de la première échéance pas encore soldée (None si tout est payé ou sans échéancier)."""
        unpaid = (state.due_date for state in self.installment_schedule if state.remaining_amount > 0)
        return next(unpaid, None)


class SaleInstallment(Base):
    """Échéance d'une vente avec dette : un montant à rembourser à une date donnée."""

    __tablename__ = "sale_installments"
    __table_args__ = (
        sa.CheckConstraint("amount > 0", name="amount_positive"),
        sa.UniqueConstraint("sale_id", "due_date"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    sale_id: Mapped[int] = mapped_column(sa.ForeignKey("sales.id", ondelete="CASCADE"), index=True)
    due_date: Mapped[date]
    amount: Mapped[Decimal] = mapped_column(MONEY)

    sale: Mapped[Sale] = relationship(back_populates="installments")


@dataclass(frozen=True)
class InstallmentState:
    """Échéance et ce qui reste dû dessus (calculé à partir des paiements, jamais stocké)."""

    due_date: date
    amount: Decimal
    remaining_amount: Decimal

    @property
    def paid_amount(self) -> Decimal:
        return self.amount - self.remaining_amount

    @property
    def status(self) -> PaymentStatus:
        if self.remaining_amount <= 0:
            return PaymentStatus.PAID
        return PaymentStatus.PARTIAL if self.remaining_amount < self.amount else PaymentStatus.UNPAID

    @property
    def is_overdue(self) -> bool:
        return self.remaining_amount > 0 and self.due_date < local_today()


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
    # Précision saisie à la vente pour cet article (taille, couleur...).
    description: Mapped[str | None] = mapped_column(UpperCaseString(255))
    quantity: Mapped[int]
    unit_price: Mapped[Decimal] = mapped_column(MONEY)
    # Prix de stock au moment de la vente : le bénéfice des ventes passées ne change pas si le prix évolue.
    unit_purchase_price: Mapped[Decimal] = mapped_column(MONEY)
    total: Mapped[Decimal] = mapped_column(MONEY)

    sale: Mapped[Sale] = relationship(back_populates="items")
