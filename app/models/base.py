"""Base déclarative, colonnes communes et types de colonnes partagés."""

from datetime import datetime
from enum import StrEnum

import sqlalchemy as sa
from sqlalchemy.engine import Dialect
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

# Noms de contraintes prévisibles : indispensable pour qu'Alembic génère des migrations stables.
NAMING_CONVENTION = {
    "ix": "ix_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_N_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


class Base(DeclarativeBase):
    metadata = sa.MetaData(naming_convention=NAMING_CONVENTION)


# Montants : 14 chiffres dont 2 décimales (jusqu'à 999 999 999 999,99).
MONEY = sa.Numeric(14, 2)


class UpperCaseString(sa.TypeDecorator[str]):
    """VARCHAR dont la valeur est toujours enregistrée en MAJUSCULES.

    Règle du projet : les noms, références, descriptions... sont stockés en majuscules.
    La conversion s'applique aussi aux valeurs comparées dans les requêtes
    (ex. `User.username == "admin"`), ce qui rend les recherches insensibles à la casse.
    """

    impl = sa.String
    cache_ok = True

    def process_bind_param(self, value: str | None, dialect: Dialect) -> str | None:
        return value.upper() if value is not None else None


def enum_column(enum_class: type[StrEnum]) -> sa.Enum:
    """Enum stocké en VARCHAR (pas de type ENUM PostgreSQL).

    Ajouter une valeur (ex. le mode de paiement MIXED) ne nécessite donc aucune migration.
    """
    return sa.Enum(
        enum_class,
        native_enum=False,
        length=30,
        validate_strings=True,
        values_callable=lambda members: [member.value for member in members],
    )


class CreatedAtMixin:
    created_at: Mapped[datetime] = mapped_column(
        sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
    )


class TimestampMixin(CreatedAtMixin):
    updated_at: Mapped[datetime] = mapped_column(
        sa.DateTime(timezone=True), server_default=sa.func.now(), onupdate=sa.func.now(), nullable=False
    )
