from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import AuditLog
from app.repositories.base import PageResult, apply_sort, date_range_filter, paginate
from app.schemas.audit import AuditFilters

SORT_FIELDS = {"created_at": AuditLog.created_at}


def list_logs(db: Session, filters: AuditFilters) -> PageResult[AuditLog]:
    stmt = select(AuditLog)
    if filters.user_id is not None:
        stmt = stmt.where(AuditLog.user_id == filters.user_id)
    if filters.action:
        stmt = stmt.where(AuditLog.action == filters.action)
    if filters.entity_type:
        stmt = stmt.where(AuditLog.entity_type == filters.entity_type)
    if filters.entity_id is not None:
        stmt = stmt.where(AuditLog.entity_id == filters.entity_id)
    stmt = stmt.where(*date_range_filter(AuditLog.created_at, filters.date_from, filters.date_to))
    stmt = apply_sort(stmt, filters.sort, SORT_FIELDS, "-created_at", AuditLog.id)
    return paginate(db, stmt, filters.page, filters.page_size)
