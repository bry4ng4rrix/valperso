from datetime import datetime
from decimal import Decimal

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import MONEY, Base, CreatedAtMixin, UpperCaseString, enum_column
from app.models.enums import CashRegisterStatus, CashTransactionType
from app.models.store import Store


class CashRegister(Base):
    """Session de caisse d'un magasin, de l'ouverture à la clôture.

    `expected_amount` est le montant théorique en caisse : il vaut `opening_amount` à
    l'ouverture puis est mis à jour à chaque opération. À la clôture,
    `difference = closing_amount - expected_amount` (négatif = manque en caisse).
    """

    __tablename__ = "cash_registers"
    __table_args__ = (
        sa.CheckConstraint("opening_amount >= 0", name="opening_amount_not_negative"),
        # Une seule caisse ouverte à la fois par magasin.
        sa.Index(
            "uq_cash_registers_one_open_per_store",
            "store_id",
            unique=True,
            postgresql_where=sa.text("status = 'OPEN'"),
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    store_id: Mapped[int] = mapped_column(sa.ForeignKey("stores.id"), index=True)
    opened_by: Mapped[int] = mapped_column(sa.ForeignKey("users.id"))
    closed_by: Mapped[int | None] = mapped_column(sa.ForeignKey("users.id"))
    opening_amount: Mapped[Decimal] = mapped_column(MONEY)
    closing_amount: Mapped[Decimal | None] = mapped_column(MONEY)
    expected_amount: Mapped[Decimal] = mapped_column(MONEY)
    difference: Mapped[Decimal | None] = mapped_column(MONEY)
    status: Mapped[CashRegisterStatus] = mapped_column(enum_column(CashRegisterStatus), index=True)
    opened_at: Mapped[datetime] = mapped_column(
        sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
    )
    closed_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))

    store: Mapped[Store] = relationship(lazy="selectin")
    transactions: Mapped[list["CashTransaction"]] = relationship(
        back_populates="cash_register", order_by="CashTransaction.id"
    )


class CashTransaction(CreatedAtMixin, Base):
    """Opération de caisse. `amount` est signé : positif = entrée d'argent, négatif = sortie."""

    __tablename__ = "cash_transactions"
    __table_args__ = (sa.CheckConstraint("amount <> 0", name="amount_not_zero"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    cash_register_id: Mapped[int] = mapped_column(sa.ForeignKey("cash_registers.id"), index=True)
    type: Mapped[CashTransactionType] = mapped_column(enum_column(CashTransactionType))
    amount: Mapped[Decimal] = mapped_column(MONEY)
    reason: Mapped[str | None] = mapped_column(UpperCaseString(255))
    reference: Mapped[str | None] = mapped_column(UpperCaseString(100))
    created_by: Mapped[int] = mapped_column(sa.ForeignKey("users.id"))

    cash_register: Mapped[CashRegister] = relationship(back_populates="transactions")
