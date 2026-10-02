from collections.abc import Iterable

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Permission, Role


def get_by_name(db: Session, name: str) -> Role | None:
    return db.scalar(select(Role).where(Role.name == name))


def list_roles(db: Session) -> list[Role]:
    return list(db.scalars(select(Role).order_by(Role.name)))


def list_permissions(db: Session) -> list[Permission]:
    return list(db.scalars(select(Permission).order_by(Permission.name)))


def get_permissions_by_ids(db: Session, permission_ids: Iterable[int]) -> list[Permission]:
    return list(db.scalars(select(Permission).where(Permission.id.in_(list(permission_ids)))))


def get_permissions_by_names(db: Session, names: Iterable[str]) -> list[Permission]:
    return list(db.scalars(select(Permission).where(Permission.name.in_(list(names)))))
