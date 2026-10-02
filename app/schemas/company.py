from datetime import datetime
from typing import Annotated

from pydantic import BeforeValidator, Field

from app.schemas.common import (
    DisplayStr,
    InputModel,
    OptionalPhone,
    OptionalUpperStr,
    ORMModel,
    UpperStr,
    blank_to_none,
)
from app.schemas.user import OptionalEmail

# Adresse web (https://...) ou chemin d'un fichier servi par le frontend ou un serveur web (/media/...).
LOGO_PATTERN = r"^(https?://|/)\S+$"
OptionalLogo = Annotated[
    Annotated[str, Field(max_length=500, pattern=LOGO_PATTERN)] | None, BeforeValidator(blank_to_none)
]


class CompanyRead(ORMModel):
    id: int
    name: DisplayStr
    logo_url: str | None
    phone: str | None
    email: str | None
    address: DisplayStr | None
    city: DisplayStr | None
    updated_at: datetime


class CompanyUpdate(InputModel):
    """Remplace les informations de la société (PUT). Les factures déjà émises ne changent pas :
    elles conservent les informations en vigueur au moment de la vente."""

    name: UpperStr = Field(min_length=2, max_length=150, examples=["Allsafe"])
    logo_url: OptionalLogo = Field(None, examples=["https://cdn.exemple.mg/allsafe/logo.png"])
    phone: OptionalPhone = Field(None, examples=["034 12 345 67"])
    email: OptionalEmail = None
    address: OptionalUpperStr = Field(None, max_length=255, examples=["Boutique H101"])
    city: OptionalUpperStr = Field(None, max_length=100, examples=["Antananarivo"])
