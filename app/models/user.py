from typing import TYPE_CHECKING

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin, UpperCaseString
from app.models.role import Role

if TYPE_CHECKING:
    from app.models.store import Store


class User(TimestampMixin, Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    first_name: Mapped[str] = mapped_column(UpperCaseString(100))
    last_name: Mapped[str] = mapped_column(UpperCaseString(100))
    username: Mapped[str] = mapped_column(UpperCaseString(50), unique=True)
    # Les emails sont normalisés en minuscules (convention des adresses email).
    email: Mapped[str | None] = mapped_column(sa.String(255), unique=True)
    phone: Mapped[str | None] = mapped_column(sa.String(30))
    password_hash: Mapped[str] = mapped_column(sa.String(255))
    role_id: Mapped[int] = mapped_column(sa.ForeignKey("roles.id"), index=True)
    # Magasin d'affectation d'un VENDEUR. Un ADMIN peut ne pas en avoir (NULL).
    store_id: Mapped[int | None] = mapped_column(sa.ForeignKey("stores.id"), index=True)
    is_active: Mapped[bool] = mapped_column(default=True, server_default=sa.true())
    # Incrémenté à chaque changement de mot de passe : les jetons émis avant deviennent invalides.
    token_version: Mapped[int] = mapped_column(default=0, server_default="0")

    role: Mapped[Role] = relationship(back_populates="users", lazy="selectin")
    store: Mapped["Store | None"] = relationship(back_populates="employees", lazy="selectin")
