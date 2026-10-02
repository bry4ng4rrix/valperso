"""Hachage des mots de passe (bcrypt) et jetons JWT (access / refresh)."""

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from enum import StrEnum
from functools import cache

import bcrypt
import jwt

from app.core.config import settings
from app.core.exceptions import AuthenticationError

JWT_ALGORITHM = "HS256"


class TokenType(StrEnum):
    ACCESS = "access"
    REFRESH = "refresh"


@dataclass(frozen=True)
class TokenData:
    user_id: int
    # Doit être égal à User.token_version : sinon le jeton a été révoqué (mot de passe changé).
    version: int


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return bcrypt.checkpw(password.encode("utf-8"), password_hash.encode("utf-8"))
    except ValueError:  # hash mal formé ou mot de passe de plus de 72 octets
        return False


@cache
def _dummy_password_hash() -> str:
    return hash_password("dummy-password")


def simulate_password_check() -> None:
    """Vérification factice pour qu'une connexion avec un utilisateur inconnu prenne autant
    de temps qu'avec un utilisateur existant (empêche de deviner les noms d'utilisateur)."""
    verify_password("not-the-password", _dummy_password_hash())


def _create_token(user_id: int, version: int, token_type: TokenType, lifetime: timedelta) -> str:
    now = datetime.now(UTC)
    payload = {
        "sub": str(user_id),
        "ver": version,
        "type": token_type.value,
        "iat": now,
        "exp": now + lifetime,
    }
    return jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=JWT_ALGORITHM)


def create_access_token(user_id: int, version: int = 0) -> str:
    lifetime = timedelta(minutes=settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES)
    return _create_token(user_id, version, TokenType.ACCESS, lifetime)


def create_refresh_token(user_id: int, version: int = 0) -> str:
    lifetime = timedelta(days=settings.JWT_REFRESH_TOKEN_EXPIRE_DAYS)
    return _create_token(user_id, version, TokenType.REFRESH, lifetime)


def decode_token(token: str, expected_type: TokenType) -> TokenData:
    """Vérifie le jeton et retourne l'utilisateur et la version qu'il contient."""
    try:
        payload = jwt.decode(
            token,
            settings.JWT_SECRET_KEY,
            algorithms=[JWT_ALGORITHM],
            options={"require": ["exp", "sub", "type"]},
        )
    except jwt.ExpiredSignatureError as exc:
        raise AuthenticationError("Jeton expiré", code="TOKEN_EXPIRED") from exc
    except jwt.InvalidTokenError as exc:
        raise AuthenticationError("Jeton invalide", code="INVALID_TOKEN") from exc

    if payload["type"] != expected_type.value:
        raise AuthenticationError("Type de jeton invalide", code="INVALID_TOKEN")
    try:
        return TokenData(user_id=int(payload["sub"]), version=int(payload.get("ver", 0)))
    except (TypeError, ValueError) as exc:
        raise AuthenticationError("Jeton invalide", code="INVALID_TOKEN") from exc


def ensure_token_is_current(data: TokenData, current_version: int) -> None:
    if data.version != current_version:
        raise AuthenticationError("Session expirée : reconnectez-vous", code="TOKEN_REVOKED")
