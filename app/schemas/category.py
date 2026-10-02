from datetime import datetime

from pydantic import Field

from app.schemas.common import (
    DisplayStr,
    InputModel,
    OptionalUpperStr,
    ORMModel,
    PageQuery,
    UpdateModel,
    UpperStr,
)


class CategorySummary(ORMModel):
    id: int
    name: DisplayStr


class CategoryRead(ORMModel):
    id: int
    name: DisplayStr
    description: DisplayStr | None
    is_active: bool
    created_at: datetime
    updated_at: datetime


class CategoryCreate(InputModel):
    name: UpperStr = Field(min_length=2, max_length=100)
    description: OptionalUpperStr = Field(None, max_length=255)


class CategoryUpdate(UpdateModel):
    NON_NULLABLE = ("name", "is_active")

    name: UpperStr | None = Field(None, min_length=2, max_length=100)
    description: OptionalUpperStr = Field(None, max_length=255)
    is_active: bool | None = None


class CategoryFilters(PageQuery):
    search: str | None = Field(None, max_length=100)
    is_active: bool | None = None
