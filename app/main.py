"""Point d'entrée de l'application FastAPI.

Lancement local : uvicorn app.main:app --reload
Documentation   : /docs (Swagger UI) et /redoc
"""

import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.router import api_router
from app.core.config import settings
from app.core.exceptions import register_exception_handlers

API_DESCRIPTION = """
API de gestion commerciale : magasins, produits, stock par magasin, transferts, ventes,
réductions, paiements, caisse, tableau de bord, audit et messagerie interne.

**Authentification** : `POST /api/v1/auth/login`, puis bouton **Authorize** avec l'access token.

**Conventions**
- Les textes (noms, références, descriptions...) sont enregistrés en MAJUSCULES et renvoyés en minuscules.
- Les montants sont calculés par le serveur ; les listes sont paginées (`page`, `size`, `sort`).
- Les erreurs ont toujours la forme `{"detail": "...", "code": "..."}`.
"""

OPENAPI_TAGS = [
    {"name": "Authentification", "description": "Connexion, renouvellement des jetons, profil."},
    {"name": "Utilisateurs", "description": "Comptes utilisateurs et rattachement à un magasin."},
    {"name": "Rôles et permissions", "description": "Contrôle d'accès basé sur les rôles (RBAC)."},
    {"name": "Magasins", "description": "Magasins, STOCK LOCAL par défaut et stock de chaque magasin."},
    {"name": "Catégories", "description": "Catégories de produits."},
    {"name": "Produits", "description": "Catalogue des produits."},
    {
        "name": "Stock",
        "description": "Entrées, sorties, ajustements, historique et transferts entre magasins.",
    },
    {"name": "Ventes", "description": "Création transactionnelle, réductions et annulation."},
    {"name": "Paiements", "description": "Paiements des ventes et règlement des ventes à crédit."},
    {"name": "Caisse", "description": "Ouverture, opérations et clôture de caisse."},
    {"name": "Tableau de bord", "description": "Statistiques calculées à partir des ventes et des stocks."},
    {"name": "Chat", "description": "Messagerie interne (module indépendant)."},
    {"name": "Audit", "description": "Journal des actions sensibles."},
]


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

    @app.get("/health", tags=["Santé"], summary="Vérifier que l'API répond")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    return app


app = create_app()
