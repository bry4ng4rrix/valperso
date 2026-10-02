"""Exceptions métier et leur conversion en réponses HTTP homogènes.

Toutes les erreurs renvoyées par l'API ont la forme :
    {"detail": "<message lisible>", "code": "<CODE_MACHINE>"}
Les erreurs de validation (422) ajoutent une liste "errors" détaillant chaque champ.

Les services lèvent les exceptions nommées ci-dessous (ProductNotFound, InsufficientStock...) ;
les routes n'ont jamais à gérer les erreurs elles-mêmes.
"""

import logging

from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy.exc import IntegrityError
from starlette.exceptions import HTTPException as StarletteHTTPException

logger = logging.getLogger(__name__)


# --- Familles d'erreurs --------------------------------------------------------------------------


class AppError(Exception):
    """Erreur applicative. Chaque sous-classe fixe son statut HTTP, son code et son message par défaut."""

    status_code: int = status.HTTP_400_BAD_REQUEST
    code: str = "BAD_REQUEST"
    default_message: str = "Requête invalide"

    def __init__(self, message: str | None = None, *, code: str | None = None) -> None:
        self.message = message or self.default_message
        if code is not None:
            self.code = code
        super().__init__(self.message)


class BusinessRuleError(AppError):
    """Une règle métier empêche l'opération (400)."""

    code = "BUSINESS_RULE_VIOLATION"


class NotFoundError(AppError):
    status_code = status.HTTP_404_NOT_FOUND
    code = "NOT_FOUND"
    default_message = "Ressource introuvable"


class ConflictError(AppError):
    """La donnée existe déjà (nom d'utilisateur, nom de magasin...)."""

    status_code = status.HTTP_409_CONFLICT
    code = "CONFLICT"


class AuthenticationError(AppError):
    status_code = status.HTTP_401_UNAUTHORIZED
    code = "NOT_AUTHENTICATED"
    default_message = "Authentification requise"


class PermissionDenied(AppError):
    status_code = status.HTTP_403_FORBIDDEN
    code = "PERMISSION_DENIED"
    default_message = "Permission insuffisante"


# --- Erreurs métier nommées ----------------------------------------------------------------------


class ProductNotFound(NotFoundError):
    code = "PRODUCT_NOT_FOUND"
    default_message = "Produit introuvable"


class StoreNotFound(NotFoundError):
    code = "STORE_NOT_FOUND"
    default_message = "Magasin introuvable"


class CustomerNotFound(NotFoundError):
    code = "CUSTOMER_NOT_FOUND"
    default_message = "Client introuvable"


class UserNotFound(NotFoundError):
    code = "USER_NOT_FOUND"
    default_message = "Utilisateur introuvable"


class InsufficientStock(BusinessRuleError):
    code = "INSUFFICIENT_STOCK"
    default_message = "Stock insuffisant"


class InactiveProduct(BusinessRuleError):
    code = "INACTIVE_PRODUCT"
    default_message = "Ce produit est désactivé"


class InactiveStore(BusinessRuleError):
    code = "INACTIVE_STORE"
    default_message = "Ce magasin est désactivé"


class InvalidTransfer(BusinessRuleError):
    code = "INVALID_TRANSFER"
    default_message = "Transfert invalide"


class SaleAlreadyCancelled(BusinessRuleError):
    code = "SALE_ALREADY_CANCELLED"
    default_message = "Cette vente est déjà annulée"


class PaymentAlreadyCompleted(BusinessRuleError):
    code = "PAYMENT_ALREADY_COMPLETED"
    default_message = "Cette vente est déjà entièrement payée"


class InvalidPayment(BusinessRuleError):
    code = "INVALID_PAYMENT"
    default_message = "Paiement invalide"


class InvalidSellingPrice(BusinessRuleError):
    code = "INVALID_SELLING_PRICE"
    default_message = "Le prix de vente doit être supérieur ou égal au prix."


class InvalidDiscount(BusinessRuleError):
    code = "INVALID_DISCOUNT"
    default_message = "Remise invalide"


class InvalidStoreAccess(PermissionDenied):
    code = "INVALID_STORE_ACCESS"
    default_message = "Vous n'avez pas accès à ce magasin"


# --- Conversion en réponses HTTP -----------------------------------------------------------------


def _error_body(detail: str, code: str, errors: list[dict] | None = None) -> dict:
    body: dict = {"detail": detail, "code": code}
    if errors is not None:
        body["errors"] = errors
    return body


async def _app_error_handler(_: Request, exc: AppError) -> JSONResponse:
    headers = {"WWW-Authenticate": "Bearer"} if isinstance(exc, AuthenticationError) else None
    return JSONResponse(_error_body(exc.message, exc.code), status_code=exc.status_code, headers=headers)


async def _validation_error_handler(_: Request, exc: RequestValidationError) -> JSONResponse:
    errors = [
        {"field": ".".join(str(part) for part in error["loc"]), "message": error["msg"]}
        for error in exc.errors()
    ]
    return JSONResponse(
        _error_body("Données invalides", "VALIDATION_ERROR", errors),
        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
    )


async def _http_error_handler(_: Request, exc: StarletteHTTPException) -> JSONResponse:
    return JSONResponse(
        _error_body(str(exc.detail), f"HTTP_{exc.status_code}"),
        status_code=exc.status_code,
        headers=getattr(exc, "headers", None),
    )


async def _integrity_error_handler(_: Request, exc: IntegrityError) -> JSONResponse:
    # Filet de sécurité : les services vérifient normalement les règles avant d'écrire.
    logger.warning("Violation de contrainte d'intégrité : %s", exc.orig)
    return JSONResponse(
        _error_body("Opération refusée : conflit avec des données existantes.", "INTEGRITY_ERROR"),
        status_code=status.HTTP_409_CONFLICT,
    )


def register_exception_handlers(app: FastAPI) -> None:
    app.add_exception_handler(AppError, _app_error_handler)
    app.add_exception_handler(RequestValidationError, _validation_error_handler)
    app.add_exception_handler(StarletteHTTPException, _http_error_handler)
    app.add_exception_handler(IntegrityError, _integrity_error_handler)
