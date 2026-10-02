from datetime import datetime
from typing import Any

from pydantic import Field

from app.schemas.common import DateRangeQuery, ORMModel, PageQuery


class AuditLogRead(ORMModel):
    id: int
    user_id: int | None
    action: str
    entity_type: str
    entity_id: int | None
    old_data: dict[str, Any] | None
    new_data: dict[str, Any] | None
    ip_address: str | None
    created_at: datetime


class AuditFilters(PageQuery, DateRangeQuery):
    user_id: int | None = None
    action: str | None = Field(None, max_length=100, description="Ex. 'sale.create'")
    entity_type: str | None = Field(None, max_length=50, description="Ex. 'product'")
    entity_id: int | None = None
