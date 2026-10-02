"""Point d'entrée de l'application FastAPI.

Lancement local : uvicorn app.main:app --reload
Documentation   : /docs (Swagger UI) et /redoc
"""

import logging

from fastapi import APIRouter, FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.router import api_router
from app.core.config import settings
from app.core.exceptions import register_exception_handlers

API_DESCRIPTION = """
API de gestion commerciale multi-magasins : utilisateurs (ADMIN / VENDEUR), magasins et Stock Local,
produits, stock par magasin, transferts, clients, ventes, remises, paiements (complets, avances,
dettes), factures, caisse, tableau de bord, audit et messagerie interne.

**Authentification** : `POST /api/v1/auth/login`, puis bouton **Authorize** avec l'access token.

**Conventions**
- Un VENDEUR travaille uniquement dans son magasin ; un ADMIN gère tous les magasins.
- Les montants, stocks et restes à payer sont calculés par le serveur.
- Les textes (noms, références, descriptions...) sont enregistrés en MAJUSCULES et renvoyés en minuscules.
- Les listes sont paginées (`page`, `page_size` ≤ 100) et triables (`sort=name` ou `sort=-created_at`).
- Les erreurs ont toujours la forme `{"detail": "...", "code": "..."}`.
"""

OPENAPI_TAGS = [
    {"name": "Authentification", "description": "Connexion, renouvellement des jetons, profil."},
    {
        "name": "Utilisateurs",
        "description": "Comptes, rôle (ADMIN / VENDEUR), affectation au magasin, statut.",
    },
    {"name": "Rôles et permissions", "description": "Contrôle d'accès basé sur les rôles (RBAC)."},
    {"name": "Magasins", "description": "Magasins, Stock Local (stock central) et employés."},
    {"name": "Catégories", "description": "Catégories de produits."},
    {"name": "Produits", "description": "Catalogue (références et noms non uniques)."},
    {"name": "Stock", "description": "Stock par magasin, seuils d'alerte, entrées, sorties, ajustements."},
    {"name": "Transferts", "description": "Déplacement de stock entre magasins (ni vente, ni perte)."},
    {"name": "Clients", "description": "Clients, historique d'achats et dettes."},
    {"name": "Ventes", "description": "Vente transactionnelle, remises, historique et annulation."},
    {"name": "Factures", "description": "Facture d'une vente."},
    {"name": "Paiements", "description": "Paiements complets, avances et soldes de dettes."},
    {"name": "Caisse", "description": "Ouverture, opérations et clôture de caisse."},
    {"name": "Tableau de bord", "description": "Statistiques calculées à partir des données existantes."},
    {"name": "Société", "description": "Informations de la société affichées sur les factures."},
    {"name": "Chat", "description": "Messagerie interne (module indépendant)."},
    {"name": "Audit", "description": "Journal des actions sensibles."},
    {"name": "Santé", "description": "Disponibilité de l'API."},
]

health_router = APIRouter(tags=["Santé"])


@health_router.get("/health", summary="Vérifier que l'API répond")
def health() -> dict[str, str]:
    """Renvoie {"status": "ok"} si l'API répond."""
    return {"status": "ok"}


def create_app() -> FastAPI:
    logging.basicConfig(level=logging.DEBUG if settings.DEBUG else logging.INFO)

    app = FastAPI(
        title=settings.APP_NAME,
        version="1.0.0",
        description=API_DESCRIPTION,
        openapi_tags=OPENAPI_TAGS,
        debug=settings.DEBUG,
    )
    if settings.cors_origins_list:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins_list,
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )
    register_exception_handlers(app)
    app.include_router(api_router, prefix="/api/v1")
    app.include_router(health_router, prefix="/api/v1")
    return app


app = create_app()
