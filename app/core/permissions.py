"""Catalogue RBAC : les deux rôles, les permissions et leur attribution par défaut.

Les codes de permission (ex. "sale.create") sont des identifiants techniques vérifiés par
chaque route. Le script de seed les enregistre en base ; un ADMIN peut ensuite modifier les
permissions des rôles avec PUT /api/v1/roles/{id}/permissions.
"""

from enum import StrEnum
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from app.models.user import User


class RoleName(StrEnum):
    """Il n'existe que deux rôles. Un co-administrateur est simplement un utilisateur ADMIN."""

    ADMIN = "ADMIN"
    VENDEUR = "VENDEUR"


class PermissionCode(StrEnum):
    DASHBOARD_VIEW = "dashboard.view"

    USER_VIEW = "user.view"
    USER_CREATE = "user.create"
    USER_UPDATE = "user.update"
    USER_DELETE = "user.delete"

    ROLE_VIEW = "role.view"
    ROLE_CREATE = "role.create"
    ROLE_UPDATE = "role.update"
    ROLE_DELETE = "role.delete"

    PERMISSION_VIEW = "permission.view"
    PERMISSION_ASSIGN = "permission.assign"

    STORE_VIEW = "store.view"
    STORE_CREATE = "store.create"
    STORE_UPDATE = "store.update"
    STORE_DELETE = "store.delete"
    STORE_STOCK_VIEW = "store.stock.view"
    STORE_TRANSFER_CREATE = "store.transfer.create"
    STORE_TRANSFER_VIEW = "store.transfer.view"
    STORE_TRANSFER_CANCEL = "store.transfer.cancel"

    PRODUCT_VIEW = "product.view"
    PRODUCT_CREATE = "product.create"
    PRODUCT_UPDATE = "product.update"
    PRODUCT_DELETE = "product.delete"

    STOCK_VIEW = "stock.view"
    STOCK_ENTRY = "stock.entry"
    STOCK_EXIT = "stock.exit"
    STOCK_ADJUST = "stock.adjust"
    STOCK_TRANSFER = "stock.transfer"

    SALE_VIEW = "sale.view"
    SALE_CREATE = "sale.create"
    SALE_CANCEL = "sale.cancel"
    SALE_DISCOUNT = "sale.discount"

    PAYMENT_VIEW = "payment.view"
    PAYMENT_CREATE = "payment.create"

    CASH_VIEW = "cash.view"
    CASH_OPEN = "cash.open"
    CASH_CLOSE = "cash.close"
    CASH_TRANSACTION = "cash.transaction"

    REPORT_VIEW = "report.view"
    AUDIT_VIEW = "audit.view"

    COMPANY_VIEW = "company.view"
    COMPANY_UPDATE = "company.update"

    CHAT_VIEW = "chat.view"
    CHAT_SEND = "chat.send"


P = PermissionCode

PERMISSION_DESCRIPTIONS: dict[PermissionCode, str] = {
    P.DASHBOARD_VIEW: "Voir le tableau de bord",
    P.USER_VIEW: "Voir les utilisateurs",
    P.USER_CREATE: "Créer des utilisateurs (y compris d'autres ADMIN)",
    P.USER_UPDATE: "Modifier les utilisateurs, leur rôle, leur magasin et leur statut",
    P.USER_DELETE: "Désactiver des utilisateurs",
    P.ROLE_VIEW: "Voir les rôles",
    P.ROLE_CREATE: "Réservée : la V1 n'a que deux rôles fixes",
    P.ROLE_UPDATE: "Modifier la description des rôles",
    P.ROLE_DELETE: "Réservée : la V1 n'a que deux rôles fixes",
    P.PERMISSION_VIEW: "Voir les permissions",
    P.PERMISSION_ASSIGN: "Attribuer les permissions aux rôles",
    P.STORE_VIEW: "Voir les magasins",
    P.STORE_CREATE: "Créer des magasins",
    P.STORE_UPDATE: "Modifier des magasins",
    P.STORE_DELETE: "Désactiver des magasins",
    P.STORE_STOCK_VIEW: "Voir le stock d'un magasin",
    P.STORE_TRANSFER_CREATE: "Transférer du stock entre magasins",
    P.STORE_TRANSFER_VIEW: "Voir les transferts",
    P.STORE_TRANSFER_CANCEL: "Annuler un transfert",
    P.PRODUCT_VIEW: "Voir les produits et catégories",
    P.PRODUCT_CREATE: "Créer des produits et catégories",
    P.PRODUCT_UPDATE: "Modifier des produits et catégories",
    P.PRODUCT_DELETE: "Désactiver des produits et catégories",
    P.STOCK_VIEW: "Voir les stocks et mouvements",
    P.STOCK_ENTRY: "Enregistrer des entrées de stock",
    P.STOCK_EXIT: "Enregistrer des sorties et pertes de stock",
    P.STOCK_ADJUST: "Ajuster le stock et les seuils d'alerte",
    P.STOCK_TRANSFER: "Transférer du stock (équivalent à store.transfer.create)",
    P.SALE_VIEW: "Voir les ventes, factures et clients",
    P.SALE_CREATE: "Créer des ventes et des clients",
    P.SALE_CANCEL: "Annuler des ventes",
    P.SALE_DISCOUNT: "Appliquer une remise",
    P.PAYMENT_VIEW: "Voir les paiements",
    P.PAYMENT_CREATE: "Enregistrer des paiements",
    P.CASH_VIEW: "Voir les caisses",
    P.CASH_OPEN: "Ouvrir une caisse",
    P.CASH_CLOSE: "Clôturer une caisse",
    P.CASH_TRANSACTION: "Enregistrer des opérations de caisse",
    P.REPORT_VIEW: "Voir les rapports et statistiques détaillés",
    P.AUDIT_VIEW: "Consulter le journal d'audit",
    P.COMPANY_VIEW: "Voir les informations de la société",
    P.COMPANY_UPDATE: "Modifier les informations de la société (factures)",
    P.CHAT_VIEW: "Lire les conversations",
    P.CHAT_SEND: "Envoyer des messages",
}

ROLE_DESCRIPTIONS: dict[RoleName, str] = {
    RoleName.ADMIN: "Administrateur : gestion complète, tous magasins",
    RoleName.VENDEUR: "Vendeur : ventes et clients de son magasin",
}

DEFAULT_ROLE_PERMISSIONS: dict[RoleName, set[PermissionCode]] = {
    RoleName.ADMIN: set(PermissionCode),
    RoleName.VENDEUR: {
        P.PRODUCT_VIEW,
        P.STOCK_VIEW,
        P.STORE_STOCK_VIEW,
        P.SALE_VIEW,
        P.SALE_CREATE,
        P.PAYMENT_VIEW,
        P.PAYMENT_CREATE,
        P.COMPANY_VIEW,
        P.CHAT_VIEW,
        P.CHAT_SEND,
    },
}

# Permissions que le rôle ADMIN doit toujours conserver, sinon plus personne ne pourrait les réattribuer.
ADMIN_REQUIRED_PERMISSIONS: set[PermissionCode] = {P.PERMISSION_VIEW, P.PERMISSION_ASSIGN, P.ROLE_VIEW}


def get_user_permissions(user: "User") -> set[str]:
    return {permission.name for permission in user.role.permissions}


def has_permission(user: "User", permission: str) -> bool:
    return permission in get_user_permissions(user)


def is_admin(user: "User") -> bool:
    return user.role.name == RoleName.ADMIN
