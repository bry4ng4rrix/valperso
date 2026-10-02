import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, UpperCaseString


class Permission(Base):
    __tablename__ = "permissions"

    id: Mapped[int] = mapped_column(primary_key=True)
    # Code technique (ex. "sale.create") : conservé tel quel, non converti en majuscules.
    name: Mapped[str] = mapped_column(sa.String(100), unique=True)
    description: Mapped[str | None] = mapped_column(UpperCaseString(255))
