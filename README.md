# API de gestion commerciale (FastAPI)

Backend d'une application de gestion commerciale multi-magasins : magasins et stock par magasin,
transferts entre magasins, catalogue produits, ventes avec réductions, paiements, caisse,
tableau de bord, audit et messagerie interne.

Il n'y a pas de frontend : l'API est documentée et testable depuis `/docs`.

---

## Sommaire

1. [Fonctionnement en bref](#1-fonctionnement-en-bref)
2. [Prérequis](#2-prérequis)
3. [Démarrage rapide avec Docker](#3-démarrage-rapide-avec-docker)
4. [Variables d'environnement](#4-variables-denvironnement)
5. [Lancement sans Docker](#5-lancement-sans-docker)
6. [Migrations](#6-migrations)
7. [Seed et premier administrateur](#7-seed-et-premier-administrateur)
8. [Tests](#8-tests)
9. [Structure du projet](#9-structure-du-projet)
10. [Conventions de code](#10-conventions-de-code)
11. [Documentation de l'API](#11-documentation-de-lapi)
12. [Rôles et permissions](#12-rôles-et-permissions)
13. [Évolutions prévues](#13-évolutions-prévues)

---

## 1. Fonctionnement en bref

### Magasins et STOCK LOCAL
- Le seed crée un magasin par défaut, **« STOCK LOCAL »** (`is_default = true`). Il ne peut être ni supprimé ni désactivé.
- Un administrateur peut créer autant de magasins que nécessaire.
- Un utilisateur **rattaché à un magasin** (`store_id`) ne travaille et ne consulte que ce magasin.
  Un utilisateur **non rattaché** (`store_id = null`, comme l'administrateur) accède à tous les magasins.
  S'il ne précise pas de magasin, ses opérations s'appliquent au STOCK LOCAL.

### Stock par magasin
- La table `store_stocks` contient la quantité de chaque produit dans chaque magasin : c'est « l'article du magasin ».
- `products.stock` est le **stock total**, c'est-à-dire la somme de tous les magasins. Il est mis à jour automatiquement.
- Chaque variation de stock passe par `stock_service.apply_stock_change()`. Cette fonction met à jour la ligne du magasin et le total du produit, puis crée un mouvement (`stock_movements`). La quantité d'un mouvement est **signée** : positive pour une entrée, négative pour une sortie.
- Statut d'un article dans un magasin : `EN_STOCK`, `STOCK_FAIBLE` (quantité ≤ `LOW_STOCK_THRESHOLD`) ou `RUPTURE` (0).

### Transferts entre magasins (`POST /api/v1/stock/transfers`)
Exemple : le STOCK LOCAL a 10 unités de l'article 1.
- **Transfert de 5** : l'article est créé dans le magasin de destination s'il n'y existait pas, avec 5 unités. Le STOCK LOCAL passe à 5.
- **Transfert des 10** : tout est déplacé. L'article reste visible dans le STOCK LOCAL, en **RUPTURE** (0).
- Chaque transfert crée un enregistrement `stock_transfers` (référence `TRF-000001`), deux mouvements (`TRANSFER_OUT` et `TRANSFER_IN`) et une entrée d'audit, dans **une seule transaction**.

### Majuscules en base, minuscules à l'affichage
- Les noms, références, descriptions, adresses, motifs, le nom du client et les noms d'utilisateur sont **enregistrés en MAJUSCULES**.
- L'API les **renvoie en minuscules**.
- Les recherches et la connexion sont donc insensibles à la casse : `admin`, `Admin` et `ADMIN` désignent le même utilisateur.
- Exceptions volontaires :
  - les emails (normalisés en minuscules) ;
  - les mots de passe ;
  - les téléphones ;
  - le contenu des messages du chat ;
  - les codes techniques : permissions (`sale.create`) et valeurs d'énumération (`CASH`, `COMPLETED`…).
- Mise en œuvre : `UpperStr` (schémas d'entrée), `UpperCaseString` (type de colonne, qui garantit la règle en base) et `DisplayStr` (schémas de sortie).

### Ventes (`POST /api/v1/sales`)
- Tout est fait dans **une seule transaction**, dans cet ordre :
  1. vérification du magasin, des produits et du stock ;
  2. calcul du sous-total, de la réduction et du total ;
  3. création de la vente et de ses lignes ;
  4. déduction du stock et création des mouvements `SALE` ;
  5. création du paiement, puis mise à jour de la caisse si le paiement est en espèces ;
  6. audit, puis COMMIT.
  
  En cas d'erreur, tout est annulé (ROLLBACK).
- Les prix et les totaux sont **toujours calculés par le serveur**. Un total envoyé par le client est ignoré.
- Il n'y a pas de table client : `customer_name` est un simple texte facultatif.
- La référence, le nom et le prix du produit sont copiés dans la ligne de vente : l'historique ne change pas si le produit est modifié ensuite.
- Les ventes simultanées sont sûres : les produits sont verrouillés (`SELECT … FOR UPDATE`, toujours par id croissant) jusqu'au COMMIT. Un test lance 6 ventes en parallèle sur un stock de 3 et vérifie que seules 3 réussissent.
- Annulation (`POST /sales/{id}/cancel`) : le stock est remis dans le magasin (mouvements `RETURN`) et les espèces sont remboursées depuis la caisse ouverte.

### Réductions
- `NONE`, `PERCENTAGE` (0 à 100 %) ou `FIXED` (montant inférieur ou égal au sous-total). Elles sont calculées par `discount_service.compute_discount()`.
- Appliquer une réduction nécessite la permission **`sale.discount`**.

### Paiements et caisse
- Modes de paiement : `CASH`, `MOBILE_MONEY`, `CARD`, `BANK_TRANSFER`, `CREDIT`. Une vente peut avoir plusieurs paiements.
- `CREDIT` signifie « payé plus tard ». Le reste à payer (`amount_due`) se règle avec `POST /api/v1/payments`.
- Seuls les paiements `CASH` passent par la caisse. Une caisse doit donc être ouverte dans le magasin pour encaisser en espèces.
- Il ne peut y avoir qu'**une caisse ouverte par magasin**.
- `expected_amount` (montant théorique) est mis à jour à chaque opération. La caisse ne peut jamais devenir négative.
- À la clôture : `difference = closing_amount - expected_amount`.

### Suppressions
La suppression d'un utilisateur, d'un magasin, d'une catégorie ou d'un produit est **logique** : l'élément passe à `is_active = false`, et l'historique (ventes, mouvements) reste intact. Un produit inactif ne peut pas être vendu.

---

## 2. Prérequis

- Docker et Docker Compose (recommandé)
- Ou bien Python 3.12+ et PostgreSQL 15+ pour un lancement sans Docker

---

## 3. Démarrage rapide avec Docker

```bash
cp .env.example .env
# Éditez .env : au minimum JWT_SECRET_KEY et FIRST_ADMIN_PASSWORD
docker compose up -d --build
```

Au démarrage, le conteneur `api` applique les migrations (`alembic upgrade head`), lance le seed, puis démarre l'API :

- API : http://localhost:8000 (port `API_PORT`)
- Swagger : http://localhost:8000/docs
- ReDoc : http://localhost:8000/redoc
- PostgreSQL : `localhost:5434` (port `POSTGRES_PORT`, choisi pour ne pas gêner un PostgreSQL local)

Commandes utiles :

```bash
docker compose logs -f api            # logs de l'API
docker compose run --rm api pytest    # lancer les tests dans le conteneur
docker compose down                   # arrêter (les données restent dans le volume)
docker compose down -v                # arrêter ET supprimer les données
```

---

## 4. Variables d'environnement

Toutes sont lues depuis `.env` (voir `.env.example`). **Ne versionnez jamais `.env`.**

| Variable | Rôle | Défaut |
|---|---|---|
| `APP_NAME` | Nom affiché dans la documentation | `Gestion Commerciale API` |
| `APP_ENV` | `development`, `test` ou `production` | `development` |
| `DEBUG` | Mode debug de FastAPI | `false` |
| `DATABASE_URL` | Connexion PostgreSQL (driver `postgresql+psycopg`) | `…@localhost:5434/commerce` |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | Base créée par Docker Compose | `commerce` |
| `POSTGRES_PORT` / `API_PORT` | Ports exposés par Docker Compose | `5434` / `8000` |
| `JWT_SECRET_KEY` | Secret de signature des jetons. **Obligatoire (≥ 32 caractères) en production** | `change-me` |
| `JWT_ACCESS_TOKEN_EXPIRE_MINUTES` | Durée de l'access token | `30` |
| `JWT_REFRESH_TOKEN_EXPIRE_DAYS` | Durée du refresh token | `7` |
| `CORS_ORIGINS` | Origines du frontend, séparées par des virgules | vide |
| `LOW_STOCK_THRESHOLD` | Seuil de stock faible | `5` |
| `TIMEZONE` | Fuseau des statistiques par jour/mois (ex. `Indian/Antananarivo`) | `UTC` |
| `FIRST_ADMIN_USERNAME` / `FIRST_ADMIN_PASSWORD` / `FIRST_ADMIN_EMAIL` | Premier administrateur créé par le seed | `admin` / — / — |
| `TEST_DATABASE_URL` | (tests) Base de test. Par défaut : `DATABASE_URL` suffixée par `_test` | — |
| `INSTALL_DEV` | (build Docker) Installe pytest dans l'image. Mettre `false` pour la production | `true` |

Pour générer un secret : `python -c "import secrets; print(secrets.token_urlsafe(48))"`

---

## 5. Lancement sans Docker

```bash
python3.12 -m venv .venv
source .venv/bin/activate              # Windows : .venv\Scripts\activate
pip install -r requirements-dev.txt
cp .env.example .env                   # adaptez DATABASE_URL à votre PostgreSQL

docker compose up -d postgres          # facultatif : PostgreSQL seul via Docker
alembic upgrade head
python -m app.seed
uvicorn app.main:app --reload
```

---

## 6. Migrations

Toute modification de la structure de la base passe par une migration Alembic. Ne modifiez jamais une base de production à la main.

```bash
alembic upgrade head                                  # appliquer les migrations
alembic revision --autogenerate -m "ajout du champ x" # générer une migration après avoir modifié un modèle
alembic check                                         # vérifier que modèles et migrations sont alignés
alembic downgrade -1                                  # annuler la dernière migration
```

Points d'attention :
- **Relisez toujours** une migration générée avant de l'appliquer.
- Les colonnes `UpperCaseString` sont écrites `sa.String(...)` dans les migrations (voir `render_item` dans `alembic/env.py`).
- Les séquences ne sont pas détectées par l'autogénération : `sale_number_seq` est créée à la main dans la migration initiale.
- Les enums sont stockés en `VARCHAR` : ajouter une valeur (ex. `MIXED`) ne nécessite **pas** de migration.
- Le test `tests/test_migrations.py` échoue si un modèle a été modifié sans migration correspondante.

---

## 7. Seed et premier administrateur

```bash
python -m app.seed                      # hors Docker
docker compose exec api python -m app.seed
```

Le script est **idempotent** : on peut le relancer sans créer de doublons. Il crée ou complète :
1. les permissions (catalogue défini dans `app/core/permissions.py`) ;
2. les rôles système `ADMIN`, `MANAGER`, `VENDEUR`, `CAISSIER`, `MAGASINIER` et leurs permissions par défaut (il n'en retire jamais) ;
3. le magasin **STOCK LOCAL** ;
4. le **premier administrateur**, à partir de `FIRST_ADMIN_USERNAME` / `FIRST_ADMIN_PASSWORD` / `FIRST_ADMIN_EMAIL`. Il n'est créé que si ce nom d'utilisateur n'existe pas encore, et seulement si `FIRST_ADMIN_PASSWORD` est défini.

Ensuite :
1. Connectez-vous via `POST /api/v1/auth/login`.
2. Collez l'`access_token` dans le bouton **Authorize** de `/docs`.
3. Créez les magasins, les utilisateurs, etc.

Pensez à changer le mot de passe de l'administrateur (`PATCH /api/v1/users/{id}`).

---

## 8. Tests

```bash
pytest                                   # avec PostgreSQL lancé (docker compose up -d postgres)
pytest tests/test_sales.py -v            # un seul module
docker compose run --rm api pytest       # dans Docker
```

- Les tests utilisent une base dédiée, `<base>_test`. Elle est créée automatiquement puis **reconstruite par les migrations Alembic** à chaque session : les migrations sont donc testées elles aussi.
- Chaque test s'exécute dans une transaction annulée à la fin : les tests sont indépendants.
- `tests/factories.py` fournit des raccourcis pour créer des magasins, produits, utilisateurs, caisses et en-têtes d'authentification.

| Fichier | Contenu |
|---|---|
| `test_auth.py` | connexion, jetons, refresh, compte désactivé, `/me` |
| `test_permissions.py` | RBAC, rôle ADMIN, modification des permissions, accès par magasin |
| `test_users.py`, `test_stores.py`, `test_products.py` | CRUD, unicité insensible à la casse, suppression logique |
| `test_stock.py` | entrées, sorties, pertes, ajustements, cohérence stock total / magasins |
| `test_transfers.py` | transfert partiel, transfert total (RUPTURE), stock insuffisant, accès |
| `test_sales.py` | les 12 cas critiques (stock, client, annulation, mouvements, **rollback**) |
| `test_discounts.py` | calcul des réductions, limites, permission `sale.discount` |
| `test_payments.py`, `test_cash.py` | crédit et règlements, caisse, écarts de clôture |
| `test_dashboard.py`, `test_audit.py`, `test_chat.py` | statistiques, journal d'audit, messagerie |
| `test_concurrency.py` | ventes simultanées réelles : jamais de survente |
| `test_migrations.py`, `test_docs.py` | modèles alignés avec les migrations, documentation OpenAPI |

---

## 9. Structure du projet

```text
app/
├── main.py              # création de l'application, CORS, routes, gestion des erreurs
├── seed.py              # données initiales (python -m app.seed)
├── core/                # configuration, base de données, sécurité/JWT, permissions, dépendances, exceptions
├── models/              # modèles SQLAlchemy et relations (aucune logique métier)
├── schemas/             # schémas Pydantic : entrées (validation), sorties (réponses), filtres
├── repositories/        # requêtes SQL (listes filtrées, verrous, agrégats)
├── services/            # logique métier, une responsabilité par fichier
│   ├── sale_service.py        # vente transactionnelle et annulation
│   ├── stock_service.py       # stock par magasin, entrées/sorties/ajustements
│   ├── transfer_service.py    # transferts entre magasins
│   ├── discount_service.py    # calcul et contrôle des réductions
│   ├── payment_service.py     # paiements, ventes à crédit
│   ├── cash_service.py        # caisses
│   ├── store_access.py        # règles d'accès aux magasins
│   └── ...                    # auth, user, role, store, category, product, dashboard, audit, chat
├── api/v1/              # routes HTTP (une par module), sans logique métier
└── utils/               # petites fonctions génériques (arrondi monétaire, texte)
alembic/                 # migrations
tests/                   # tests pytest
scripts/entrypoint.sh    # migrations + seed au démarrage du conteneur
```

Chemin d'une requête : **route** (`api/v1`) → **service** (règles métier) → **repository** / modèles → PostgreSQL.

---

## 10. Conventions de code

- **Transactions** : chaque service d'écriture se termine par `db.commit()`. Si une exception est levée avant, `get_db()` fait un ROLLBACK : il ne reste jamais de donnée partielle.
- **Erreurs** : les services lèvent des exceptions métier (`app/core/exceptions.py`). Toutes les erreurs ont la forme `{"detail": "...", "code": "..."}` :

  | Exception | Code HTTP | Exemple |
  |---|---|---|
  | `BusinessRuleError` | 400 | stock insuffisant, caisse fermée |
  | `AuthenticationError` | 401 | jeton absent ou expiré |
  | `PermissionDeniedError` | 403 | permission ou magasin non autorisé |
  | `NotFoundError` | 404 | ressource introuvable |
  | `ConflictError` | 409 | référence ou nom d'utilisateur déjà utilisé |
  | (validation) | 422 | données invalides, avec une liste `errors` par champ |

- **Permissions** : chaque route déclare `require_permission(PermissionCode.X)`. Elles sont toujours vérifiées côté serveur.
- **Audit** : `audit_service.record()` s'ajoute à la transaction en cours. L'action et sa trace sont donc enregistrées ensemble, ou pas du tout.
- **Listes** : elles sont paginées (`page`, `size` ≤ 100) et triables (`sort=name` ou `sort=-created_at`), avec recherche (`search`) et filtres propres à chaque ressource. Un champ de tri non autorisé renvoie une erreur 400.
- **Montants** : `Numeric(14, 2)` en base, `Decimal` en Python, nombre dans le JSON. L'arrondi est commercial, au centime.
- **Dates** : elles sont stockées avec fuseau horaire. Les filtres `date_from` (inclus) et `date_to` (exclu) acceptent l'ISO 8601.

### Ajouter un module
1. Créez le modèle dans `app/models/`, puis importez-le dans `app/models/__init__.py`.
2. Générez et relisez la migration : `alembic revision --autogenerate`.
3. Écrivez les schémas, le repository si des requêtes sont nécessaires, puis le service.
4. Ajoutez la route dans `app/api/v1/`, puis enregistrez-la dans `router.py`.
5. Ajoutez la permission dans `app/core/permissions.py` et relancez le seed.
6. Écrivez les tests.

---

## 11. Documentation de l'API

- **Swagger UI** : `/docs`. Connectez-vous avec `POST /api/v1/auth/login`, puis utilisez le bouton **Authorize**.
- **ReDoc** : `/redoc`
- **OpenAPI** : `/openapi.json`

| Préfixe | Principales routes |
|---|---|
| `/api/v1/auth` | `POST /login`, `POST /refresh`, `GET /me` |
| `/api/v1/users` | CRUD utilisateurs (suppression = désactivation) |
| `/api/v1/roles`, `/api/v1/permissions` | rôles, `PUT /roles/{id}/permissions`, liste des permissions |
| `/api/v1/stores` | CRUD magasins, **`GET /stores/{id}/stock`** (articles du magasin et statut) |
| `/api/v1/categories`, `/api/v1/products` | catalogue |
| `/api/v1/stock` | `POST /entry`, `/exit`, `/adjust`, `GET /movements`, **`POST`/`GET /transfers`** |
| `/api/v1/sales` | `POST` (création), `GET`, `POST /{id}/cancel` |
| `/api/v1/payments` | liste, règlement d'une vente à crédit |
| `/api/v1/cash` | `POST /registers/open`, `/registers/{id}/close`, `GET /registers/current`, opérations |
| `/api/v1/dashboard` | `/summary`, `/sales`, `/top-products`, `/low-stock` |
| `/api/v1/chat` | conversations, messages, lecture, suppression |
| `/api/v1/audit` | journal d'audit filtrable |

Exemple de vente :

```json
POST /api/v1/sales
{
  "customer_name": "Jean",
  "items": [{"product_id": 1, "quantity": 2}],
  "discount_type": "PERCENTAGE",
  "discount_value": 10,
  "payment": {"method": "CASH"}
}
```

---

## 12. Rôles et permissions

L'**ADMIN** possède toujours toutes les permissions. Les autres rôles reçoivent par défaut :

| Rôle | Permissions par défaut |
|---|---|
| MANAGER | tableau de bord, rapports, catégories, produits, stock (y compris transferts), ventes (y compris réductions et annulation), paiements, caisse, consultation des magasins, des utilisateurs et de l'audit, chat |
| VENDEUR | tableau de bord, consultation catalogue et stock, création et consultation des ventes, consultation des paiements, chat |
| CAISSIER | tableau de bord, consultation catalogue, ventes, paiements et règlements, caisse complète, chat |
| MAGASINIER | catégories et produits (sans suppression), stock complet (y compris transferts), consultation des magasins, chat |

Les permissions se modifient via `PUT /api/v1/roles/{id}/permissions`. Seul un ADMIN peut attribuer le rôle ADMIN.

Liste complète des codes :
- `dashboard.view`, `report.view`
- `category.*`, `product.*` (view, create, update, delete)
- `stock.view`, `stock.entry`, `stock.exit`, `stock.adjust`, `stock.transfer`
- `sale.view`, `sale.create`, `sale.cancel`, `sale.discount`
- `payment.view`, `payment.create`
- `cash.view`, `cash.open`, `cash.close`, `cash.transaction`
- `store.*`, `user.*`, `role.*` (view, create, update, delete)
- `audit.view`
- `chat.view`, `chat.send`

---

## 13. Évolutions prévues

- **Paiement MIXED** : une vente accepterait une liste de paiements dont la somme vaut le total, chacun enregistré via `payment_service.record_payment()`. Rien ne change en base : chaque paiement est une ligne, et les modes sont stockés en texte.
- **Chat en temps réel** : un endpoint WebSocket pourra réutiliser `chat_service.send_message()`. Redis ne deviendra utile que pour diffuser les messages entre plusieurs instances de l'API.
- **Révocation des refresh tokens** : les jetons sont aujourd'hui sans état. Les révoquer avant expiration nécessiterait une table (ou Redis) de jetons invalidés.
