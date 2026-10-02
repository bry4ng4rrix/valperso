"""Dépendances FastAPI partagées : session, utilisateur connecté, permissions, adresse IP."""

from typing import Annotated, Any

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.exceptions import AuthenticationError, PermissionDenied
from app.core.permissions import PermissionCode, has_permission
from app.core.security import TokenType, decode_token
from app.models import User

DbSession = Annotated[Session, Depends(get_db)]

bearer_scheme = HTTPBearer(
    auto_error=False,
    description="Access token obtenu via POST /api/v1/auth/login",
)


def get_current_user(
    db: DbSession,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
) -> User:
    """L'utilisateur est toujours retrouvé à partir du JWT, jamais à partir d'un champ de la requête."""
    if credentials is None:
        raise AuthenticationError()
    user_id = decode_token(credentials.credentials, TokenType.ACCESS)
    user = db.get(User, user_id)
    if user is None or not user.is_active:
        raise AuthenticationError("Utilisateur introuvable ou désactivé")
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]


def require_permission(*permissions: PermissionCode) -> Any:
    """Exige TOUTES les permissions listées.

    Usage : `user: Annotated[User, require_permission(PermissionCode.SALE_CREATE)]`
    """

    def check_permissions(current_user: CurrentUser) -> User:
        missing = [code.value for code in permissions if not has_permission(current_user, code)]
        if missing:
            raise PermissionDenied(f"Permission requise : {', '.join(missing)}")
        return current_user

    return Depends(check_permissions)


def require_any_permission(*permissions: PermissionCode) -> Any:
    """Exige AU MOINS UNE des permissions listées (permissions équivalentes)."""

    def check_permissions(current_user: CurrentUser) -> User:
        if not any(has_permission(current_user, code) for code in permissions):
            raise PermissionDenied(f"Permission requise : {' ou '.join(code.value for code in permissions)}")
        return current_user

    return Depends(check_permissions)


def get_client_ip(request: Request) -> str | None:
    return request.client.host if request.client else None


ClientIP = Annotated[str | None, Depends(get_client_ip)]
