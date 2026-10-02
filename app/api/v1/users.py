from typing import Annotated

from fastapi import APIRouter, Query, status

from app.api.responses import PROTECTED, error_responses
from app.core.deps import ClientIP, DbSession, require_permission
from app.core.permissions import PermissionCode as P
from app.models import User
from app.schemas.common import Page
from app.schemas.user import UserCreate, UserFilters, UserRead, UserUpdate
from app.services import user_service

router = APIRouter(prefix="/users", tags=["Utilisateurs"], responses=PROTECTED)


@router.get("", response_model=Page[UserRead], summary="Lister les utilisateurs")
def list_users(
    db: DbSession,
    filters: Annotated[UserFilters, Query()],
    _: Annotated[User, require_permission(P.USER_VIEW)],
):
    """Tri possible : `username`, `last_name`, `created_at`."""
    return user_service.list_users(db, filters)


@router.get(
    "/{user_id}", response_model=UserRead, summary="Détail d'un utilisateur", responses=error_responses(404)
)
def get_user(user_id: int, db: DbSession, _: Annotated[User, require_permission(P.USER_VIEW)]):
    return user_service.get_user(db, user_id)


@router.post(
    "",
    response_model=UserRead,
    status_code=status.HTTP_201_CREATED,
    summary="Créer un utilisateur",
    responses=error_responses(404, 409),
)
def create_user(
    data: UserCreate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.USER_CREATE)],
):
    """Seul un administrateur peut attribuer le rôle ADMIN. `store_id` null = accès à tous les magasins."""
    return user_service.create_user(db, current_user, data, ip_address)


@router.patch(
    "/{user_id}",
    response_model=UserRead,
    summary="Modifier un utilisateur",
    responses=error_responses(400, 404, 409),
)
def update_user(
    user_id: int,
    data: UserUpdate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.USER_UPDATE)],
):
    """Seuls les champs envoyés sont modifiés. Envoyer `password` réinitialise le mot de passe."""
    return user_service.update_user(db, current_user, user_id, data, ip_address)


@router.delete(
    "/{user_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Désactiver un utilisateur",
    responses=error_responses(400, 404),
)
def delete_user(
    user_id: int,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.USER_DELETE)],
) -> None:
    """Suppression logique : le compte est désactivé, son historique est conservé."""
    user_service.delete_user(db, current_user, user_id, ip_address)
