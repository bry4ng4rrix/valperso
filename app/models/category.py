from typing import TYPE_CHECKING

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin, UpperCaseString

if TYPE_CHECKING:
    from app.models.product import Product


class Category(TimestampMixin, Base):
    __tablename__ = "categories"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(UpperCaseString(100), unique=True)
    description: Mapped[str | None] = mapped_column(UpperCaseString(255))
    is_active: Mapped[bool] = mapped_column(default=True, server_default=sa.true())

    products: Mapped[list["Product"]] = relationship(back_populates="category")
