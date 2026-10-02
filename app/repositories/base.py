"""Outils communs aux repositories : pagination, tri, recherche et filtres de dates."""

from collections.abc import Mapping
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from sqlalchemy import ColumnElement, Select, func, or_, select
from sqlalchemy.orm import Session

from app.core.exceptions import BusinessRuleError
from app.utils.text import LIKE_ESCAPE_CHAR, contains_pattern


@dataclass
class PageResult[T]:
    """Une page de résultats. Convertie en schéma `Page[...]` par les routes."""

    items: list[T]
    total: int
    page: int
    page_size: int


def _count(db: Session, stmt: Select[Any]) -> int:
    return db.scalar(select(func.count()).select_from(stmt.order_by(None).subquery())) or 0


def paginate(db: Session, stmt: Select[Any], page: int, page_size: int) -> PageResult[Any]:
    """Page d'objets : la requête sélectionne une entité (ex. select(Product))."""
    items = list(db.scalars(stmt.limit(page_size).offset((page - 1) * page_size)))
    return PageResult(items=items, total=_count(db, stmt), page=page, page_size=page_size)


def paginate_rows(db: Session, stmt: Select[Any], page: int, page_size: int) -> PageResult[Any]:
    """Page de lignes à plusieurs colonnes (ex. un client et ses totaux calculés)."""
    items = list(db.execute(stmt.limit(page_size).offset((page - 1) * page_size)))
    return PageResult(items=items, total=_count(db, stmt), page=page, page_size=page_size)


def apply_sort(
    stmt: Select[Any],
    sort: str | None,
    allowed: Mapping[str, ColumnElement[Any]],
    default: str,
    tiebreaker: ColumnElement[Any],
) -> Select[Any]:
    """Trie selon `sort` ("champ" ou "-champ"). Seuls les champs de `allowed` sont acceptés.

    `tiebreaker` (en général l'id) garantit un ordre stable d'une page à l'autre.
    """
    value = sort or default
    descending = value.startswith("-")
    field = value.removeprefix("-")
    column = allowed.get(field)
    if column is None:
        raise BusinessRuleError(
            f"Tri impossible sur '{field}'. Champs autorisés : {', '.join(sorted(allowed))}",
            code="INVALID_SORT",
        )
    if descending:
        return stmt.order_by(column.desc(), tiebreaker.desc())
    return stmt.order_by(column.asc(), tiebreaker.asc())


def search_filter(term: str, *columns: ColumnElement[Any]) -> ColumnElement[bool]:
    """Condition « l'une des colonnes contient le terme », insensible à la casse."""
    pattern = contains_pattern(term.strip())
    return or_(*(column.ilike(pattern, escape=LIKE_ESCAPE_CHAR) for column in columns))


def date_range_filter(
    column: ColumnElement[Any], date_from: datetime | None, date_to: datetime | None
) -> list[ColumnElement[bool]]:
    conditions: list[ColumnElement[bool]] = []
    if date_from is not None:
        conditions.append(column >= date_from)
    if date_to is not None:
        conditions.append(column < date_to)
    return conditions
