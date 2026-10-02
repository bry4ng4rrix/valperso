"""Types et schémas réutilisés par tous les modules."""

from datetime import datetime
from decimal import Decimal
from math import ceil
from typing import Annotated, ClassVar

from pydantic import (
    AfterValidator,
    BaseModel,
    BeforeValidator,
    ConfigDict,
    Field,
    PlainSerializer,
    computed_field,
    model_validator,
)

# --- Textes : MAJUSCULES en base, minuscules à l'affichage -------------------------------------


def _upper(value: str | None) -> str | None:
    return value.upper() if value is not None else None


def blank_to_none(value: object) -> object:
    return None if isinstance(value, str) and not value.strip() else value


# En entrée : le texte est converti en majuscules avant d'atteindre les services.
UpperStr = Annotated[str, AfterValidator(_upper)]
# En entrée, champ facultatif : une chaîne vide devient null.
OptionalUpperStr = Annotated[str | None, BeforeValidator(blank_to_none), AfterValidator(_upper)]
# En sortie : le texte stocké en majuscules est renvoyé en minuscules dans les réponses JSON.
DisplayStr = Annotated[str, PlainSerializer(str.lower, return_type=str, when_used="json")]


# --- Montants ------------------------------------------------------------------------------------

_money_to_json = PlainSerializer(float, return_type=float, when_used="json")

# Montant positif ou nul, 2 décimales maximum. Renvoyé en nombre dans le JSON.
Money = Annotated[Decimal, Field(ge=0, max_digits=14, decimal_places=2), _money_to_json]
# Montant signé (ajustement, opération de sortie...).
SignedMoney = Annotated[Decimal, Field(max_digits=14, decimal_places=2), _money_to_json]


# --- Modèles de base -----------------------------------------------------------------------------


class ORMModel(BaseModel):
    """Schéma de réponse construit directement depuis un objet SQLAlchemy."""

    model_config = ConfigDict(from_attributes=True)


class InputModel(BaseModel):
    """Schéma d'entrée : les espaces superflus sont retirés des chaînes."""

    model_config = ConfigDict(str_strip_whitespace=True)


class UpdateModel(InputModel):
    """Schéma de modification partielle (PATCH) : seuls les champs envoyés sont modifiés.

    Les champs listés dans NON_NULLABLE peuvent être omis mais pas envoyés à null.
    """

    NON_NULLABLE: ClassVar[tuple[str, ...]] = ()

    @model_validator(mode="after")
    def _reject_null_values(self):
        for field in self.NON_NULLABLE:
            if field in self.model_fields_set and getattr(self, field) is None:
                raise ValueError(f"Le champ '{field}' ne peut pas être null")
        return self

    def changes(self) -> dict:
        return self.model_dump(exclude_unset=True)


# --- Pagination et filtres -----------------------------------------------------------------------


class Pagination(BaseModel):
    page: int = Field(1, ge=1, description="Numéro de page (commence à 1)")
    page_size: int = Field(20, ge=1, le=100, description="Nombre d'éléments par page (100 maximum)")


class PageQuery(Pagination):
    """Paramètres communs des listes : pagination et tri.

    `sort` accepte un nom de champ, préfixé par "-" pour un tri décroissant (ex. "-created_at").
    """

    sort: str | None = Field(None, max_length=50, description="Champ de tri, ex. 'name' ou '-created_at'")


class DateRangeQuery(BaseModel):
    date_from: datetime | None = Field(None, description="Date/heure de début incluse (ISO 8601)")
    date_to: datetime | None = Field(None, description="Date/heure de fin exclue (ISO 8601)")

    @model_validator(mode="after")
    def _check_range(self):
        if self.date_from and self.date_to and self.date_from >= self.date_to:
            raise ValueError("date_from doit être antérieure à date_to")
        return self


class Page[T](BaseModel):
    model_config = ConfigDict(from_attributes=True)

    items: list[T]
    total: int = Field(description="Nombre total d'éléments correspondant aux filtres")
    page: int
    page_size: int

    @computed_field
    @property
    def pages(self) -> int:
        return ceil(self.total / self.page_size) if self.page_size else 0


# --- Réponses d'erreur (documentation OpenAPI) --------------------------------------------------


class FieldError(BaseModel):
    field: str
    message: str


class ErrorResponse(BaseModel):
    detail: str = Field(examples=["Stock insuffisant pour le produit P-001"])
    code: str = Field(examples=["INSUFFICIENT_STOCK"])
    errors: list[FieldError] | None = None


# --- Champs de contact ---------------------------------------------------------------------------

PHONE_PATTERN = r"^\+?[0-9 ().-]{6,30}$"

Phone = Annotated[str, Field(pattern=PHONE_PATTERN, max_length=30)]
OptionalPhone = Annotated[Phone | None, BeforeValidator(blank_to_none)]
