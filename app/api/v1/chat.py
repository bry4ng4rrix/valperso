from typing import Annotated

from fastapi import APIRouter, Query, Response, status

from app.api.responses import PROTECTED, error_responses
from app.core.deps import DbSession, require_permission
from app.core.permissions import PermissionCode as P
from app.models import User
from app.schemas.chat import ConversationCreate, ConversationRead, MessageCreate, MessageRead
from app.schemas.common import Page, Pagination
from app.services import chat_service

router = APIRouter(prefix="/chat", tags=["Chat"], responses=PROTECTED)


@router.get("/conversations", response_model=list[ConversationRead], summary="Mes conversations")
def list_conversations(db: DbSession, current_user: Annotated[User, require_permission(P.CHAT_VIEW)]):
    """Les plus récentes d'abord, avec le nombre de messages non lus."""
    return chat_service.list_conversations(db, current_user)


@router.post(
    "/conversations",
    response_model=ConversationRead,
    status_code=status.HTTP_201_CREATED,
    summary="Démarrer une conversation",
    responses=error_responses(400, 404),
)
def create_conversation(
    data: ConversationCreate,
    response: Response,
    db: DbSession,
    current_user: Annotated[User, require_permission(P.CHAT_SEND)],
):
    """PRIVATE : un autre utilisateur ; si la conversation existe déjà, elle est renvoyée (200).
    GROUP : un nom et un ou plusieurs participants."""
    conversation, created = chat_service.create_conversation(db, current_user, data)
    if not created:
        response.status_code = status.HTTP_200_OK
    return conversation


@router.get(
    "/conversations/{conversation_id}",
    response_model=ConversationRead,
    summary="Détail d'une conversation",
    responses=error_responses(404),
)
def get_conversation(
    conversation_id: int, db: DbSession, current_user: Annotated[User, require_permission(P.CHAT_VIEW)]
):
    return chat_service.get_conversation(db, current_user, conversation_id)


@router.get(
    "/conversations/{conversation_id}/messages",
    response_model=Page[MessageRead],
    summary="Messages d'une conversation",
    responses=error_responses(404),
)
def list_messages(
    conversation_id: int,
    db: DbSession,
    pagination: Annotated[Pagination, Query()],
    current_user: Annotated[User, require_permission(P.CHAT_VIEW)],
):
    """Du plus récent au plus ancien."""
    return chat_service.list_messages(db, current_user, conversation_id, pagination)


@router.post(
    "/conversations/{conversation_id}/messages",
    response_model=MessageRead,
    status_code=status.HTTP_201_CREATED,
    summary="Envoyer un message",
    responses=error_responses(404),
)
def send_message(
    conversation_id: int,
    data: MessageCreate,
    db: DbSession,
    current_user: Annotated[User, require_permission(P.CHAT_SEND)],
):
    return chat_service.send_message(db, current_user, conversation_id, data)


@router.post(
    "/conversations/{conversation_id}/read",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Marquer la conversation comme lue",
    responses=error_responses(404),
)
def mark_as_read(
    conversation_id: int, db: DbSession, current_user: Annotated[User, require_permission(P.CHAT_VIEW)]
) -> None:
    chat_service.mark_as_read(db, current_user, conversation_id)


@router.delete(
    "/messages/{message_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Supprimer un de mes messages",
    responses=error_responses(404),
)
def delete_message(
    message_id: int, db: DbSession, current_user: Annotated[User, require_permission(P.CHAT_SEND)]
) -> None:
    chat_service.delete_message(db, current_user, message_id)
