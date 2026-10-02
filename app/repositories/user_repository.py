from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.permissions import RoleName
from app.models import Role, User
from app.repositories.base import PageResult, apply_sort, paginate, search_filter
from app.schemas.common import Pagination
from app.schemas.user import UserFilters

SORT_FIELDS = {
    "username": User.username,
    "last_name": User.last_name,
    "created_at": User.created_at,
}


def get_by_username(db: Session, username: str) -> User | None:
    # La colonne est en majuscules : la comparaison est donc insensible à la casse.
    return db.scalar(select(User).where(User.username == username))


def get_by_email(db: Session, email: str) -> User | None:
    return db.scalar(select(User).where(User.email == email.lower()))


def list_users(db: Session, filters: UserFilters) -> PageResult[User]:
    stmt = select(User)
    if filters.search:
        stmt = stmt.where(
            search_filter(filters.search, User.first_name, User.last_name, User.username, User.email)
        )
    if filters.role is not None:
        stmt = stmt.join(User.role).where(Role.name == filters.role)
    if filters.store_id is not None:
        stmt = stmt.where(User.store_id == filters.store_id)
    if filters.is_active is not None:
        stmt = stmt.where(User.is_active == filters.is_active)
    stmt = apply_sort(stmt, filters.sort, SORT_FIELDS, "username", User.id)
    return paginate(db, stmt, filters.page, filters.page_size)


def list_store_employees(db: Session, store_id: int, pagination: Pagination) -> PageResult[User]:
    stmt = select(User).where(User.store_id == store_id).order_by(User.last_name, User.id)
    return paginate(db, stmt, pagination.page, pagination.page_size)


def count_active_admins(db: Session) -> int:
    stmt = (
        select(func.count())
        .select_from(User)
        .join(User.role)
        .where(Role.name == RoleName.ADMIN, User.is_active.is_(True))
    )
    return db.scalar(stmt) or 0
