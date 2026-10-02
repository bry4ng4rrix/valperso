from typing import TYPE_CHECKING

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, UpperCaseString
from app.models.permission import Permission

if TYPE_CHECKING:
    from app.models.user import User

# Table d'association RolePermission (role_id, permission_id).
role_permissions = sa.Table(
    "role_permissions",
    Base.metadata,
    sa.Column("role_id", sa.ForeignKey("roles.id", ondelete="CASCADE"), primary_key=True),
    sa.Column("permission_id", sa.ForeignKey("permissions.id", ondelete="CASCADE"), primary_key=True),
)


class Role(Base):
    """Il n'existe que deux rôles : ADMIN et VENDEUR (créés par le seed)."""

    __tablename__ = "roles"

    id: Mapped[int] = mapped_column(primary_key=True)
    # Code du rôle (ADMIN / VENDEUR), affiché tel quel.
    name: Mapped[str] = mapped_column(sa.String(50), unique=True)
    description: Mapped[str | None] = mapped_column(UpperCaseString(255))

    permissions: Mapped[list[Permission]] = relationship(
        secondary=role_permissions, lazy="selectin", order_by=Permission.name
    )
    users: Mapped[list["User"]] = relationship(back_populates="role")
