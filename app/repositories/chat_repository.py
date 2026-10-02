from sqlalchemy import and_, func, or_, select
from sqlalchemy.orm import Session, aliased

from app.models import Conversation, ConversationMember, Message
from app.models.enums import ConversationType
from app.repositories.base import PageResult, paginate


def get_member(db: Session, conversation_id: int, user_id: int) -> ConversationMember | None:
    return db.get(ConversationMember, (conversation_id, user_id))


def list_conversations_with_unread(db: Session, user_id: int) -> list[tuple[Conversation, int]]:
    """Conversations de l'utilisateur, les plus récentes d'abord, avec leur nombre de messages non lus."""
    unread_count = (
        select(func.count(Message.id))
        .where(
            Message.conversation_id == Conversation.id,
            Message.sender_id != user_id,
            Message.is_deleted.is_(False),
            or_(
                ConversationMember.last_read_at.is_(None),
                Message.created_at > ConversationMember.last_read_at,
            ),
        )
        .correlate(Conversation, ConversationMember)
        .scalar_subquery()
    )
    stmt = (
        select(Conversation, unread_count)
        .join(
            ConversationMember,
            and_(
                ConversationMember.conversation_id == Conversation.id, ConversationMember.user_id == user_id
            ),
        )
        .order_by(Conversation.updated_at.desc(), Conversation.id.desc())
    )
    return [(conversation, count) for conversation, count in db.execute(stmt)]


def find_private_conversation(db: Session, user_id: int, other_user_id: int) -> Conversation | None:
    first_member = aliased(ConversationMember)
    second_member = aliased(ConversationMember)
    stmt = (
        select(Conversation)
        .join(first_member, first_member.conversation_id == Conversation.id)
        .join(second_member, second_member.conversation_id == Conversation.id)
        .where(
            Conversation.type == ConversationType.PRIVATE,
            first_member.user_id == user_id,
            second_member.user_id == other_user_id,
        )
        .limit(1)
    )
    return db.scalar(stmt)


def list_messages(db: Session, conversation_id: int, page: int, page_size: int) -> PageResult[Message]:
    stmt = (
        select(Message)
        .where(Message.conversation_id == conversation_id)
        .order_by(Message.created_at.desc(), Message.id.desc())
    )
    return paginate(db, stmt, page, page_size)
