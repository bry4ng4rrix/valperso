from fastapi import APIRouter

from app.api.responses import error_responses
from app.core.dependencies import ClientIP, CurrentUser, DbSession
from app.schemas.auth import LoginRequest, RefreshRequest, TokenResponse
from app.schemas.user import UserProfile
from app.services import auth_service

router = APIRouter(prefix="/auth", tags=["Authentification"])


@router.post(
    "/login",
    response_model=TokenResponse,
    summary="Se connecter",
    responses=error_responses(401, 403, 422),
)
def login(data: LoginRequest, db: DbSession, ip_address: ClientIP):
    """Vérifie l'identifiant (nom d'utilisateur ou email, insensible à la casse) et le mot de passe.

    Retourne un **access token**, à envoyer dans l'en-tête `Authorization: Bearer <token>`,
    et un **refresh token** pour en obtenir un nouveau sans se reconnecter.
    """
    return auth_service.login(db, data, ip_address)


@router.post(
    "/refresh",
    response_model=TokenResponse,
    summary="Renouveler les jetons",
    responses=error_responses(401, 422),
)
def refresh(data: RefreshRequest, db: DbSession):
    """Échange un refresh token valide contre une nouvelle paire de jetons."""
    return auth_service.refresh(db, data)


@router.get(
    "/me",
    response_model=UserProfile,
    summary="Profil de l'utilisateur connecté",
    responses=error_responses(401),
)
def me(current_user: CurrentUser):
    """Retourne l'utilisateur connecté, son rôle et la liste de ses permissions effectives."""
    return auth_service.get_profile(current_user)
