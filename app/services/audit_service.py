"""Journal d'audit : enregistrement et consultation des actions sensibles.

`record()` ajoute l'entrée à la transaction en cours, sans COMMIT : elle est donc
enregistrée (ou annulée) en même temps que l'opération qu'elle décrit.
"""

from typing import Any

from fastapi.encoders import jsonable_encoder
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.exceptions import NotFoundError
from app.models import AuditLog
from app.repositories import audit_repository
from app.repositories.base import PageResult
from app.schemas.audit import AuditFilters


def snapshot(schema: type[BaseModel], obj: Any) -> dict[str, Any]:
    """Copie JSON d'un objet, telle qu'enregistrée dans old_data / new_data."""
    return jsonable_encoder(schema.model_validate(obj).model_dump())


def record(
    db: Session,
    *,
    user_id: int | None,
    action: str,
    entity_type: str,
    entity_id: int | None = None,
    old_data: dict[str, Any] | None = None,
    new_data: dict[str, Any] | None = None,
    ip_address: str | None = None,
) -> AuditLog:
    log = AuditLog(
        user_id=user_id,
        action=action,
        entity_type=entity_type,
        entity_id=entity_id,
        old_data=old_data,
        new_data=new_data,
        ip_address=ip_address,
    )
    db.add(log)
    return log


def list_logs(db: Session, filters: AuditFilters) -> PageResult[AuditLog]:
    return audit_repository.list_logs(db, filters)


def get_log(db: Session, log_id: int) -> AuditLog:
    log = db.get(AuditLog, log_id)
    if log is None:
        raise NotFoundError("Entrée d'audit introuvable")
    return log
