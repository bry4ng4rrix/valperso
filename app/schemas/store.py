from datetime import datetime

from pydantic import Field

from app.schemas.common import (
    DisplayStr,
    InputModel,
    OptionalPhone,
    OptionalUpperStr,
    ORMModel,
    PageQuery,
    UpdateModel,
    UpperStr,
)


class StoreSummary(ORMModel):
    id: int
    name: DisplayStr
    is_central: bool


class StoreRead(ORMModel):
    id: int
    name: DisplayStr
    address: DisplayStr | None
    phone: str | None
    is_central: bool = Field(description="Vrai pour le Stock Local (stock central)")
    is_active: bool
    created_at: datetime
    updated_at: datetime


class StoreCreate(InputModel):
    """Un magasin se crée sans vendeur : les utilisateurs y sont affectés ensuite."""

    name: UpperStr = Field(min_length=2, max_length=150)
    address: OptionalUpperStr = Field(None, max_length=255)
    phone: OptionalPhone = None


class StoreUpdate(UpdateModel):
    NON_NULLABLE = ("name", "is_active")

    name: UpperStr | None = Field(None, min_length=2, max_length=150)
    address: OptionalUpperStr = Field(None, max_length=255)
    phone: OptionalPhone = None
    is_active: bool | None = None


class StoreFilters(PageQuery):
    search: str | None = Field(None, max_length=100, description="Recherche sur le nom ou l'adresse")
    is_active: bool | None = None
