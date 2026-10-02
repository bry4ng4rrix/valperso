from typing import Any

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, CreatedAtMixin


class AuditLog(CreatedAtMixin, Base):
    """Journal des actions sensibles (qui a fait quoi, quand, depuis quelle adresse IP)."""

    __tablename__ = "audit_logs"
    __table_args__ = (
        sa.Index("ix_audit_logs_entity", "entity_type", "entity_id"),
        sa.Index("ix_audit_logs_created_at", "created_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int | None] = mapped_column(sa.ForeignKey("users.id", ondelete="SET NULL"), index=True)
    # Codes techniques (ex. "sale.create", "product") : conservés tels quels.
    action: Mapped[str] = mapped_column(sa.String(100), index=True)
    entity_type: Mapped[str] = mapped_column(sa.String(50))
    entity_id: Mapped[int | None]
    old_data: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    new_data: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    ip_address: Mapped[str | None] = mapped_column(sa.String(45))
