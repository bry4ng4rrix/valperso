from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin, UpperCaseString, enum_column
from app.models.enums import ConversationType
from app.models.user import User


class Conversation(TimestampMixin, Base):
    __tablename__ = "conversations"

    id: Mapped[int] = mapped_column(primary_key=True)
    type: Mapped[ConversationType] = mapped_column(enum_column(ConversationType))
    name: Mapped[str | None] = mapped_column(UpperCaseString(150))  # obligatoire pour un groupe
    created_by: Mapped[int] = mapped_column(sa.ForeignKey("users.id"))

    members: Mapped[list["ConversationMember"]] = relationship(
        back_populates="conversation", cascade="all, delete-orphan", lazy="selectin"
    )


class ConversationMember(Base):
    __tablename__ = "conversation_members"

    conversation_id: Mapped[int] = mapped_column(
        sa.ForeignKey("conversations.id", ondelete="CASCADE"), primary_key=True
    )
    user_id: Mapped[int] = mapped_column(sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    joined_at: Mapped[datetime] = mapped_column(
        sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
    )
    last_read_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))

    conversation: Mapped[Conversation] = relationship(back_populates="members")
    user: Mapped[User] = relationship(lazy="selectin")


class Message(TimestampMixin, Base):
    __tablename__ = "messages"
    __table_args__ = (sa.Index("ix_messages_conversation_created", "conversation_id", "created_at"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    conversation_id: Mapped[int] = mapped_column(sa.ForeignKey("conversations.id", ondelete="CASCADE"))
    sender_id: Mapped[int] = mapped_column(sa.ForeignKey("users.id"))
    # Texte libre d'une conversation : conservé tel quel (pas de conversion en majuscules).
    content: Mapped[str] = mapped_column(sa.Text)
    is_deleted: Mapped[bool] = mapped_column(default=False, server_default=sa.false())
