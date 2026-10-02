from typing import TYPE_CHECKING

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin, UpperCaseString

if TYPE_CHECKING:
    from app.models.sale import Sale


class Customer(TimestampMixin, Base):
    """Client. Le téléphone est facultatif, mais obligatoire pour une vente avec avance ou à crédit."""

    __tablename__ = "customers"
    __table_args__ = (sa.Index("ix_customers_name", "last_name", "first_name"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    first_name: Mapped[str] = mapped_column(UpperCaseString(100))
    last_name: Mapped[str] = mapped_column(UpperCaseString(100))
    phone: Mapped[str | None] = mapped_column(sa.String(30), index=True)

    sales: Mapped[list["Sale"]] = relationship(back_populates="customer")
