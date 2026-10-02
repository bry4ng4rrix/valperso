from datetime import datetime

from pydantic import Field, model_validator

from app.models.enums import ConversationType
from app.schemas.common import DisplayStr, InputModel, OptionalUpperStr, ORMModel
from app.schemas.user import UserSummary


class ConversationCreate(InputModel):
    type: ConversationType
    name: OptionalUpperStr = Field(None, max_length=150, description="Obligatoire pour un groupe")
    member_ids: list[int] = Field(
        min_length=1, max_length=50, description="Autres participants (exactement 1 pour PRIVATE)"
    )

    @model_validator(mode="after")
    def _check_conversation(self):
        if len(set(self.member_ids)) != len(self.member_ids):
            raise ValueError("Un participant ne peut être ajouté qu'une seule fois")
        if self.type == ConversationType.PRIVATE and len(self.member_ids) != 1:
            raise ValueError("Une conversation privée concerne exactement un autre utilisateur")
        if self.type == ConversationType.GROUP and not self.name:
            raise ValueError("Un groupe doit avoir un nom")
        return self


class ConversationMemberRead(ORMModel):
    user: UserSummary
    joined_at: datetime
    last_read_at: datetime | None


class ConversationRead(ORMModel):
    id: int
    type: ConversationType
    name: DisplayStr | None
    created_by: int
    created_at: datetime
    updated_at: datetime
    members: list[ConversationMemberRead]
    unread_count: int = 0


class MessageCreate(InputModel):
    content: str = Field(min_length=1, max_length=2000)


class MessageRead(ORMModel):
    id: int
    conversation_id: int
    sender_id: int
    content: str | None = Field(description="null si le message a été supprimé")
    is_deleted: bool
    created_at: datetime
    updated_at: datetime

    @model_validator(mode="after")
    def _hide_deleted_content(self):
        if self.is_deleted:
            self.content = None
        return self
