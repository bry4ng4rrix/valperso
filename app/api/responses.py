"""Réponses d'erreur documentées dans OpenAPI (/docs et /redoc)."""

from typing import Any

from app.schemas.common import ErrorResponse

_DESCRIPTIONS = {
    400: "Règle métier non respectée (stock insuffisant, caisse fermée...)",
    401: "Non authentifié ou jeton invalide",
    403: "Permission insuffisante ou magasin non autorisé",
    404: "Ressource introuvable",
    409: "Conflit avec une donnée existante (doublon)",
    422: "Données invalides",
}


def error_responses(*status_codes: int) -> dict[int | str, dict[str, Any]]:
    return {code: {"model": ErrorResponse, "description": _DESCRIPTIONS[code]} for code in status_codes}


# Réponses communes à toutes les routes protégées.
PROTECTED = error_responses(401, 403, 422)
