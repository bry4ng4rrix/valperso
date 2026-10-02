from datetime import datetime
from typing import Annotated

from pydantic import AfterValidator, BeforeValidator, EmailStr, Field

from app.core.permissions import RoleName
from app.schemas.common import (
    DisplayStr,
    InputModel,
    OptionalPhone,
    ORMModel,
    PageQuery,
    UpperStr,
    blank_to_none,
)
from app.schemas.role import RoleSummary
from app.schemas.store import StoreSummary

USERNAME_PATTERN = r"^[A-Za-z0-9._-]+$"


def _check_password_bytes(value: str) -> str:
    # bcrypt ne prend en compte que les 72 premiers octets d'un mot de passe.
    if len(value.encode("utf-8")) > 72:
        raise ValueError("Le mot de passe ne doit pas dépasser 72 octets")
    return value


def _lower(value: str | None) -> str | None:
    return value.lower() if value else value


Password = Annotated[str, Field(min_length=8, max_length=72), AfterValidator(_check_password_bytes)]
# Les emails sont stockés en minuscules (convention des adresses email).
OptionalEmail = Annotated[EmailStr | None, BeforeValidator(blank_to_none), AfterValidator(_lower)]
Username = Annotated[UpperStr, Field(min_length=3, max_length=50, pattern=USERNAME_PATTERN)]
PersonName = Annotated[UpperStr, Field(min_length=1, max_length=100)]


class UserSummary(ORMModel):
    """Auteur d'une opération (vente, paiement, mouvement...), avec son rôle."""

    id: int
    username: DisplayStr
    first_name: DisplayStr
    last_name: DisplayStr
    role: RoleSummary


class UserRead(ORMModel):
    id: int
    first_name: DisplayStr
    last_name: DisplayStr
    username: DisplayStr
    email: str | None
    phone: str | None
    role: RoleSummary
    store_id: int | None = Field(description="Magasin d'affectation (null pour un ADMIN non affecté)")
    store: StoreSummary | None
    is_active: bool
    created_at: datetime
    updated_at: datetime


class UserProfile(UserRead):
    permissions: list[str]


class UserCreate(InputModel):
    first_name: PersonName
    last_name: PersonName
    username: Username
    email: OptionalEmail = None
    phone: OptionalPhone = None
    password: Password
    role: RoleName = RoleName.VENDEUR
    store_id: int | None = Field(None, gt=0, description="Magasin d'affectation (recommandé pour un VENDEUR)")
    is_active: bool = True


class UserUpdate(InputModel):
    """Remplace les informations du compte (PUT). Le mot de passe n'est modifié que s'il est envoyé.
    Le rôle, le magasin et le statut se changent avec les routes dédiées."""

    first_name: PersonName
    last_name: PersonName
    username: Username
    email: OptionalEmail = None
    phone: OptionalPhone = None
    password: Password | None = None


class UserRoleUpdate(InputModel):
    role: RoleName


class UserStoreUpdate(InputModel):
    store_id: int | None = Field(gt=0, description="Nouveau magasin, ou null pour retirer l'affectation")


class UserStatusUpdate(InputModel):
    is_active: bool


class UserFilters(PageQuery):
    search: str | None = Field(None, max_length=100, description="Nom, prénom, username ou email")
    role: RoleName | None = None
    store_id: int | None = None
    is_active: bool | None = None
