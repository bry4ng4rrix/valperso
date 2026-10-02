from decimal import Decimal

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, column_property, mapped_column, relationship

from app.models.base import MONEY, Base, CreatedAtMixin, UpperCaseString, enum_column
from app.models.enums import PaymentMethod
from app.models.sale import Sale
from app.models.user import User


class Payment(CreatedAtMixin, Base):
    """Somme réellement encaissée pour une vente. Une vente peut en avoir plusieurs (avance puis solde) :
    chaque paiement est conservé, l'historique n'est jamais écrasé."""

    __tablename__ = "payments"
    __table_args__ = (
        sa.CheckConstraint("amount > 0", name="amount_positive"),
        sa.Index("ix_payments_created_at", "created_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    sale_id: Mapped[int] = mapped_column(sa.ForeignKey("sales.id"), index=True)
    method: Mapped[PaymentMethod] = mapped_column(enum_column(PaymentMethod))
    amount: Mapped[Decimal] = mapped_column(MONEY)
    # Référence externe : n° de transaction mobile money, de virement...
    reference: Mapped[str | None] = mapped_column(UpperCaseString(100))
    created_by: Mapped[int] = mapped_column(sa.ForeignKey("users.id"))

    sale: Mapped[Sale] = relationship(back_populates="payments")
    creator: Mapped[User] = relationship(lazy="selectin")


# Montant payé d'une vente = somme de ses paiements, calculée par PostgreSQL à chaque lecture.
Sale.amount_paid = column_property(
    sa.select(sa.func.coalesce(sa.func.sum(Payment.amount), 0))
    .where(Payment.sale_id == Sale.id)
    .correlate_except(Payment)
    .scalar_subquery()
)
