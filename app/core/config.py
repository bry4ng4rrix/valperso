"""Configuration centralisée, lue depuis les variables d'environnement et le fichier `.env`."""

from datetime import time
from typing import Literal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

DEFAULT_JWT_SECRET = "change-me"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    APP_NAME: str = "Gestion Commerciale API"
    APP_ENV: Literal["development", "test", "production"] = "development"
    DEBUG: bool = False

    DATABASE_URL: str = "postgresql+psycopg://commerce:commerce@localhost:5434/commerce"

    JWT_SECRET_KEY: str = DEFAULT_JWT_SECRET
    JWT_ACCESS_TOKEN_EXPIRE_MINUTES: int = Field(default=30, gt=0)
    JWT_REFRESH_TOKEN_EXPIRE_DAYS: int = Field(default=7, gt=0)

    # Origines autorisées, séparées par des virgules : "http://localhost:3000,https://app.exemple.mg"
    CORS_ORIGINS: str = ""

    # Premier administrateur créé par le seed (python -m app.seed).
    INITIAL_ADMIN_USERNAME: str = "admin"
    INITIAL_ADMIN_EMAIL: str | None = None
    INITIAL_ADMIN_PASSWORD: str | None = None

    # Nom de la société créé par le seed ; il se modifie ensuite avec PUT /api/v1/company.
    COMPANY_NAME: str = "Ma Société"

    # Mot de passe des comptes de démonstration (python -m app.seed_demo). Jamais en production.
    DEMO_PASSWORD: str | None = None

    # Seuil d'alerte appliqué aux nouvelles lignes de stock (modifiable ensuite ligne par ligne).
    DEFAULT_ALERT_THRESHOLD: int = Field(default=5, ge=0)
    # Fuseau horaire des statistiques par jour/mois et de l'année des numéros de facture.
    TIMEZONE: str = "UTC"

    # Caisses : ouverture et fermeture automatiques chaque jour, à l'heure de CASH_SCHEDULE_TIMEZONE.
    CASH_AUTO_SCHEDULE: bool = True
    CASH_AUTO_OPEN_TIME: time = time(6, 0)
    CASH_AUTO_CLOSE_TIME: time = time(19, 0)
    CASH_SCHEDULE_TIMEZONE: str = "Indian/Antananarivo"

    @property
    def cors_origins_list(self) -> list[str]:
        return [origin.strip() for origin in self.CORS_ORIGINS.split(",") if origin.strip()]

    @model_validator(mode="after")
    def _check_cash_schedule(self) -> "Settings":
        if self.CASH_AUTO_OPEN_TIME >= self.CASH_AUTO_CLOSE_TIME:
            raise ValueError("CASH_AUTO_OPEN_TIME doit être avant CASH_AUTO_CLOSE_TIME.")
        try:
            ZoneInfo(self.CASH_SCHEDULE_TIMEZONE)
        except ZoneInfoNotFoundError as error:
            raise ValueError(f"Fuseau horaire inconnu : {self.CASH_SCHEDULE_TIMEZONE}") from error
        return self

    @model_validator(mode="after")
    def _check_production_secret(self) -> "Settings":
        weak_secret = self.JWT_SECRET_KEY == DEFAULT_JWT_SECRET or len(self.JWT_SECRET_KEY) < 32
        if self.APP_ENV == "production" and weak_secret:
            raise ValueError("JWT_SECRET_KEY doit contenir au moins 32 caractères aléatoires en production.")
        return self


settings = Settings()
