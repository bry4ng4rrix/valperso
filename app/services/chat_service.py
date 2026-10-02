"""Messagerie interne (module indépendant : les ventes et le stock n'en dépendent pas).

Toute la logique est ici et non dans les routes : un futur endpoint WebSocket pourra
réutiliser directement `send_message()`.
"""

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.exceptions import BusinessRuleError, NotFoundError, PermissionDeniedError
from app.models import Conversation, ConversationMember, Message, User
from app.models.enums import ConversationType
from app.repositories import chat_repository
from app.repositories.base import PageResult
from app.schemas.chat import ConversationCreate, ConversationRead, MessageCreate
from app.schemas.common import Pagination


def _get_membership(db: Session, user: User, conversation_id: int) -> ConversationMember:
    if db.get(Conversation, conversation_id) is None:
        raise NotFoundError("Conversation introuvable")
    member = chat_repository.get_member(db, conversation_id, user.id)
    if member is None:
        raise PermissionDeniedError("Vous ne participez pas à cette conversation")
    return member


def _get_active_users(db: Session, user_ids: list[int]) -> list[User]:
    users = [db.get(User, user_id) for user_id in user_ids]
    unknown = [
        user_id for user_id, user in zip(user_ids, users, strict=True) if user is None or not user.is_active
    ]
    if unknown:
        raise NotFoundError(f"Utilisateur(s) introuvable(s) ou désactivé(s) : {unknown}")
    return [user for user in users if user is not None]


def list_conversations(db: Session, user: User) -> list[ConversationRead]:
    return [
        ConversationRead.model_validate(conversation).model_copy(update={"unread_count": unread})
        for conversation, unread in chat_repository.list_conversations_with_unread(db, user.id)
    ]


def create_conversation(db: Session, user: User, data: ConversationCreate) -> tuple[Conversation, bool]:
    """Crée une conversation. Pour une conversation privée qui existe déjà, la renvoie (created=False)."""
    if user.id in data.member_ids:
        raise BusinessRuleError("Ne vous ajoutez pas vous-même : vous êtes membre automatiquement")
    others = _get_active_users(db, data.member_ids)

    if data.type == ConversationType.PRIVATE:
        existing = chat_repository.find_private_conversation(db, user.id, others[0].id)
        if existing is not None:
            return existing, False

    conversation = Conversation(
        type=data.type,
        name=data.name if data.type == ConversationType.GROUP else None,
        created_by=user.id,
        members=[ConversationMember(user=member) for member in [user, *others]],
    )
    db.add(conversation)
    db.commit()
    return conversation, True


def get_conversation(db: Session, user: User, conversation_id: int) -> Conversation:
    _get_membership(db, user, conversation_id)
    return db.get(Conversation, conversation_id)


def list_messages(
    db: Session, user: User, conversation_id: int, pagination: Pagination
) -> PageResult[Message]:
    """Messages du plus récent au plus ancien."""
    _get_membership(db, user, conversation_id)
    return chat_repository.list_messages(db, conversation_id, pagination.page, pagination.size)


def send_message(db: Session, user: User, conversation_id: int, data: MessageCreate) -> Message:
    member = _get_membership(db, user, conversation_id)
    message = Message(conversation_id=conversation_id, sender_id=user.id, content=data.content)
    db.add(message)
    member.last_read_at = func.now()
    member.conversation.updated_at = func.now()
    db.commit()
    return message


def mark_as_read(db: Session, user: User, conversation_id: int) -> None:
    member = _get_membership(db, user, conversation_id)
    member.last_read_at = func.now()
    db.commit()


def delete_message(db: Session, user: User, message_id: int) -> None:
    """Suppression logique, réservée à l'auteur du message."""
    message = db.get(Message, message_id)
    if message is None:
        raise NotFoundError("Message introuvable")
    _get_membership(db, user, message.conversation_id)
    if message.sender_id != user.id:
        raise PermissionDeniedError("Vous ne pouvez supprimer que vos propres messages")
    message.is_deleted = True
    db.commit()
