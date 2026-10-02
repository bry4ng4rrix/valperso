from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.exceptions import AuthenticationError, PermissionDeniedError
from app.core.permissions import get_user_permissions
from app.core.security import (
    TokenType,
    create_access_token,
    create_refresh_token,
    decode_token,
    simulate_password_check,
    verify_password,
)
from app.models import User
from app.repositories import user_repository
from app.schemas.auth import LoginRequest, RefreshRequest, TokenResponse
from app.schemas.user import UserProfile, UserRead
from app.services import audit_service


def _issue_tokens(user: User) -> TokenResponse:
    return TokenResponse(
        access_token=create_access_token(user.id),
        refresh_token=create_refresh_token(user.id),
        expires_in=settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES * 60,
    )


def _record_failed_login(
    db: Session, user: User | None, username: str, reason: str, ip_address: str | None
) -> None:
    audit_service.record(
        db,
        user_id=user.id if user else None,
        action="auth.login_failed",
        entity_type="user",
        entity_id=user.id if user else None,
        new_data={"username": username.upper(), "reason": reason},
        ip_address=ip_address,
    )
    # Commit immédiat : la tentative est tracée même si la requête se termine en erreur.
    db.commit()


def login(db: Session, data: LoginRequest, ip_address: str | None = None) -> TokenResponse:
    user = user_repository.get_by_username(db, data.username)
    if user is None:
        simulate_password_check()
    if user is None or not verify_password(data.password, user.password_hash):
        _record_failed_login(db, user, data.username, "INVALID_CREDENTIALS", ip_address)
        raise AuthenticationError("Nom d'utilisateur ou mot de passe incorrect", code="INVALID_CREDENTIALS")
    if not user.is_active:
        _record_failed_login(db, user, data.username, "ACCOUNT_DISABLED", ip_address)
        raise PermissionDeniedError("Ce compte est désactivé", code="ACCOUNT_DISABLED")

    audit_service.record(
        db, user_id=user.id, action="auth.login", entity_type="user", entity_id=user.id, ip_address=ip_address
    )
    db.commit()
    return _issue_tokens(user)


def refresh(db: Session, data: RefreshRequest) -> TokenResponse:
    user_id = decode_token(data.refresh_token, TokenType.REFRESH)
    user = db.get(User, user_id)
    if user is None or not user.is_active:
        raise AuthenticationError("Utilisateur introuvable ou désactivé")
    return _issue_tokens(user)


def get_profile(user: User) -> UserProfile:
    profile = UserRead.model_validate(user).model_dump()
    return UserProfile(**profile, permissions=sorted(get_user_permissions(user)))
