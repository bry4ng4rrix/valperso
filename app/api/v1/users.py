from typing import Annotated

from fastapi import APIRouter, Query, status

from app.api.responses import PROTECTED, error_responses
from app.core.dependencies import ClientIP, DbSession, require_permission
from app.core.permissions import PermissionCode as P
from app.models import User
from app.schemas.common import Page
from app.schemas.user import (
    UserCreate,
    UserFilters,
    UserRead,
    UserRoleUpdate,
    UserStatusUpdate,
    UserStoreUpdate,
    UserUpdate,
)
from app.services import user_service

router = APIRouter(prefix="/users", tags=["Utilisateurs"], responses=PROTECTED)


@router.get("", response_model=Page[UserRead], summary="Lister les utilisateurs")
def list_users(
    db: DbSession,
    filters: Annotated[UserFilters, Query()],
    _: Annotated[User, require_permission(P.USER_VIEW)],
):
    """Filtres : `store_id`, `role` (ADMIN / VENDEUR), `is_active`, `search` (nom, prénom, username, email).
    Tri : `username`, `last_name`, `created_at`."""
    return user_service.list_users(db, filters)


@router.get("/{user_id}", response_model=UserRead, summary="Détail d'un utilisateur", responses=error_responses(404))
def get_user(user_id: int, db: DbSession, _: Annotated[User, require_permission(P.USER_VIEW)]):
    return user_service.get_user(db, user_id)


@router.post(
    "",
    response_model=UserRead,
    status_code=status.HTTP_201_CREATED,
    summary="Créer un utilisateur (VENDEUR ou ADMIN)",
    responses=error_responses(400, 404, 409),
)
def create_user(
    data: UserCreate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.USER_CREATE)],
):
    """Un ADMIN peut créer d'autres ADMIN (co-administrateurs). Un VENDEUR est normalement
    affecté à un magasin (`store_id`) ; un ADMIN peut ne pas en avoir."""
    return user_service.create_user(db, current_user, data, ip_address)


@router.put(
    "/{user_id}",
    response_model=UserRead,
    summary="Modifier les informations d'un utilisateur",
    responses=error_responses(404, 409),
)
def update_user(
    user_id: int,
    data: UserUpdate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.USER_UPDATE)],
):
    """Remplace nom, prénom, username, email et téléphone. Le mot de passe n'est changé que s'il est envoyé."""
    return user_service.update_user(db, current_user, user_id, data, ip_address)


@router.put(
    "/{user_id}/role",
    response_model=UserRead,
    summary="Changer le rôle",
    responses=error_responses(400, 404),
)
def change_role(
    user_id: int,
    data: UserRoleUpdate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.USER_UPDATE)],
):
    """ADMIN ou VENDEUR. Le dernier ADMIN actif ne peut pas être rétrogradé."""
    return user_service.change_role(db, current_user, user_id, data, ip_address)


@router.put(
    "/{user_id}/store",
    response_model=UserRead,
    summary="Affecter à un magasin / changer de magasin",
    responses=error_responses(400, 404),
)
def change_store(
    user_id: int,
    data: UserStoreUpdate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.USER_UPDATE)],
):
    """`store_id` = magasin d'affectation, ou `null` pour retirer l'affectation."""
    return user_service.change_store(db, current_user, user_id, data, ip_address)


@router.put(
    "/{user_id}/status",
    response_model=UserRead,
    summary="Activer / désactiver un compte",
    responses=error_responses(400, 404),
)
def change_status(
    user_id: int,
    data: UserStatusUpdate,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.USER_UPDATE)],
):
    """Un compte désactivé ne peut plus se connecter. Impossible sur son propre compte ou le dernier ADMIN."""
    return user_service.change_status(db, current_user, user_id, data, ip_address)


@router.delete(
    "/{user_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Supprimer (désactiver) un utilisateur",
    responses=error_responses(400, 404),
)
def delete_user(
    user_id: int,
    db: DbSession,
    ip_address: ClientIP,
    current_user: Annotated[User, require_permission(P.USER_DELETE)],
) -> None:
    """Suppression logique : le compte est désactivé, son historique (ventes, paiements) est conservé."""
    user_service.delete_user(db, current_user, user_id, ip_address)
