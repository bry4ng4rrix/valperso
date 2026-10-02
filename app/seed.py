"""Données initiales : permissions, rôles système, STOCK LOCAL et premier administrateur.

Usage : python -m app.seed

Le script est idempotent : il peut être relancé sans créer de doublons. Il ajoute ce qui
manque mais ne retire jamais une permission accordée manuellement à un rôle.
"""

import logging

from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import SessionLocal
from app.core.permissions import (
    DEFAULT_ROLE_PERMISSIONS,
    PERMISSION_DESCRIPTIONS,
    ROLE_DESCRIPTIONS,
    PermissionCode,
    RoleName,
)
from app.core.security import hash_password
from app.models import Permission, Role, Store, User
from app.repositories import role_repository, store_repository, user_repository
from app.services.store_service import DEFAULT_STORE_NAME

logger = logging.getLogger("seed")


def seed_permissions(db: Session) -> dict[str, Permission]:
    existing = {p.name: p for p in role_repository.list_permissions(db)}
    for code in PermissionCode:
        permission = existing.get(code.value)
        if permission is None:
            permission = Permission(name=code.value)
            db.add(permission)
            existing[code.value] = permission
        permission.description = PERMISSION_DESCRIPTIONS[code]
    db.flush()
    return existing


def seed_roles(db: Session, permissions: dict[str, Permission]) -> dict[str, Role]:
    roles: dict[str, Role] = {}
    for role_name in RoleName:
        role = role_repository.get_by_name(db, role_name.value)
        if role is None:
            role = Role(name=role_name.value, description=ROLE_DESCRIPTIONS[role_name])
            db.add(role)
        granted = {permission.name for permission in role.permissions}
        for code in DEFAULT_ROLE_PERMISSIONS[role_name]:
            if code.value not in granted:
                role.permissions.append(permissions[code.value])
        roles[role_name.value] = role
    db.flush()
    return roles


def seed_default_store(db: Session) -> Store:
    store = store_repository.get_default(db)
    if store is None:
        store = Store(name=DEFAULT_STORE_NAME, is_default=True, is_active=True)
        db.add(store)
        db.flush()
        logger.info("Magasin par défaut « %s » créé", DEFAULT_STORE_NAME)
    return store


def seed_admin(db: Session, admin_role: Role) -> User | None:
    if user_repository.get_by_username(db, settings.FIRST_ADMIN_USERNAME) is not None:
        return None
    if not settings.FIRST_ADMIN_PASSWORD:
        logger.warning("FIRST_ADMIN_PASSWORD non défini : aucun administrateur créé")
        return None

    admin = User(
        first_name="Administrateur",
        last_name="Principal",
        username=settings.FIRST_ADMIN_USERNAME.upper(),
        email=settings.FIRST_ADMIN_EMAIL.lower() if settings.FIRST_ADMIN_EMAIL else None,
        password_hash=hash_password(settings.FIRST_ADMIN_PASSWORD),
        role=admin_role,
        store_id=None,  # non rattaché : accès à tous les magasins
    )
    db.add(admin)
    db.flush()
    logger.info("Administrateur « %s » créé", settings.FIRST_ADMIN_USERNAME)
    return admin


def run_seed(db: Session) -> None:
    permissions = seed_permissions(db)
    roles = seed_roles(db, permissions)
    seed_default_store(db)
    seed_admin(db, roles[RoleName.ADMIN.value])
    db.commit()


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    with SessionLocal() as db:
        run_seed(db)
    logger.info("Seed terminé")


if __name__ == "__main__":
    main()
