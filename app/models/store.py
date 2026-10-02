from typing import TYPE_CHECKING

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin, UpperCaseString

if TYPE_CHECKING:
    from app.models.stock import Stock
    from app.models.user import User


class Store(TimestampMixin, Base):
    """Magasin. Il se crée sans vendeur : les utilisateurs y sont affectés ensuite (User.store_id)."""

    __tablename__ = "stores"
    __table_args__ = (
        # Un seul magasin central : le « STOCK LOCAL » créé par le seed.
        sa.Index(
            "uq_stores_single_central", "is_central", unique=True, postgresql_where=sa.text("is_central")
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(UpperCaseString(150), unique=True)
    address: Mapped[str | None] = mapped_column(UpperCaseString(255))
    phone: Mapped[str | None] = mapped_column(sa.String(30))
    # Vrai uniquement pour le Stock Local, le stock central qui alimente les autres magasins.
    is_central: Mapped[bool] = mapped_column(default=False, server_default=sa.false())
    is_active: Mapped[bool] = mapped_column(default=True, server_default=sa.true())

    employees: Mapped[list["User"]] = relationship(back_populates="store")
    stocks: Mapped[list["Stock"]] = relationship(back_populates="store")
