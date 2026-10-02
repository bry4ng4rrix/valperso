# API de gestion commerciale multi-magasins (FastAPI)

Backend REST d'une application de gestion commerciale. Il couvre :
- les utilisateurs, avec deux rôles (ADMIN et VENDEUR) et des permissions ;
- les magasins, dont un stock central appelé **Stock Local** ;
- le catalogue (catégories, produits) et le stock par magasin, avec ses seuils d'alerte ;
- les transferts entre magasins ;
- les clients, les ventes avec remise et les paiements (complets, avances, dettes avec échéance) ;
- les factures avec les informations de la société ;
- la caisse, le tableau de bord, l'historique, l'audit et une messagerie interne.

Il n'y a pas de frontend. L'API se teste depuis **Swagger** (`/docs`) ou **ReDoc** (`/redoc`).

Stack : Python 3.12+, FastAPI, SQLAlchemy 2, PostgreSQL, Alembic, Pydantic v2, JWT, bcrypt, pytest, Docker.

---

## Sommaire

1. [Démarrage rapide](#1-démarrage-rapide)
2. [Architecture](#2-architecture)
3. [Configuration (.env)](#3-configuration-env)
4. [Docker et PostgreSQL](#4-docker-et-postgresql)
5. [Alembic (migrations)](#5-alembic-migrations)
6. [Seed et premier ADMIN](#6-seed-et-premier-admin)
7. [Utilisateurs, rôles et permissions](#7-utilisateurs-rôles-et-permissions)
8. [Magasins et Stock Local](#8-magasins-et-stock-local)
9. [Produits, stocks et seuils](#9-produits-stocks-et-seuils)
10. [Transferts](#10-transferts)
11. [Clients, ventes, paiements et dettes](#11-clients-ventes-paiements-et-dettes)
12. [Société et factures](#12-société-et-factures)
13. [Caisse](#13-caisse)
14. [Tableau de bord](#14-tableau-de-bord)
15. [Audit](#15-audit)
16. [Tests](#16-tests)
17. [Documentation de l'API (Swagger, ReDoc)](#17-documentation-de-lapi-swagger-redoc)
18. [Conventions de code](#18-conventions-de-code)

---

## 1. Démarrage rapide

```bash
cp .env.example .env      # puis modifier JWT_SECRET_KEY, INITIAL_ADMIN_PASSWORD et COMPANY_NAME
docker compose up --build
```

Le conteneur `api` lance automatiquement les migrations et le seed, puis démarre l'API :

- API : http://localhost:8000/api/v1 (port `API_PORT`)
- Swagger : http://localhost:8000/docs
- ReDoc : http://localhost:8000/redoc

Ensuite :
1. Connectez-vous avec `POST /api/v1/auth/login` (identifiants `INITIAL_ADMIN_*`).
2. Collez l'`access_token` dans le bouton **Authorize** de Swagger.

---

## 2. Architecture

```text
app/
├── main.py              # application FastAPI, CORS, routes, gestion des erreurs
├── seed.py              # données initiales (python -m app.seed)
├── core/                # config, database, security (bcrypt, JWT), dependencies, permissions, exceptions
├── models/              # modèles SQLAlchemy et relations, un fichier par entité
├── schemas/             # schémas Pydantic : validation des entrées, format des réponses, filtres
├── repositories/        # requêtes SQL réutilisables (listes filtrées, verrous, agrégats)
├── services/            # TOUTE la logique métier, une responsabilité par fichier
├── api/v1/              # routes HTTP : requête -> dépendances -> service -> réponse
├── utils/               # petites fonctions génériques (arrondi monétaire, texte)
└── tests/               # tests pytest
alembic/                 # migrations
scripts/entrypoint.sh    # migrations + seed au démarrage du conteneur
```

Chemin d'une requête : **route** (`api/v1`) → **service** (règles métier) → **repository** / modèles → PostgreSQL.

| Service | Responsabilité |
|---|---|
| `store_access.py` | isolation des magasins (règle de sécurité commune à tous les modules) |
| `user_service.py`, `role_service.py`, `auth_service.py` | comptes, rôles, permissions, connexion |
| `store_service.py`, `category_service.py`, `product_service.py` | magasins et catalogue (règle de prix) |
| `stock_service.py`, `stock_transfer_service.py` | stock par magasin, mouvements, transferts |
| `customer_service.py`, `sale_service.py`, `discount_service.py` | clients, ventes, remises, historique |
| `payment_service.py`, `cash_service.py` | paiements, avances, dettes, caisse |
| `company_service.py` | informations de la société (factures) |
| `dashboard_service.py`, `audit_service.py`, `chat_service.py` | statistiques, audit, messagerie |

Il n'y a ni microservices, ni CQRS, ni file de messages, ni Redis : HTTP et PostgreSQL suffisent pour la V1.

---

## 3. Configuration (.env)

Copiez `.env.example` en `.env`. **Ne versionnez jamais `.env`** : il est ignoré par git.

| Variable | Rôle | Défaut |
|---|---|---|
| `APP_NAME`, `APP_ENV`, `DEBUG` | nom affiché, environnement (`development`, `test`, `production`), mode debug | — |
| `DATABASE_URL` | connexion PostgreSQL (driver `postgresql+psycopg`) | `…@localhost:5434/commerce` |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | base créée par Docker Compose | `commerce` |
| `POSTGRES_PORT`, `API_PORT` | ports exposés sur la machine | `5434`, `8000` |
| `JWT_SECRET_KEY` | secret de signature des jetons. **Au moins 32 caractères en production** (sinon l'API refuse de démarrer) | `change-me` |
| `JWT_ACCESS_TOKEN_EXPIRE_MINUTES` / `JWT_REFRESH_TOKEN_EXPIRE_DAYS` | durée des jetons | `30` / `7` |
| `CORS_ORIGINS` | origines autorisées (frontend), séparées par des virgules | vide |
| `INITIAL_ADMIN_EMAIL` / `INITIAL_ADMIN_USERNAME` / `INITIAL_ADMIN_PASSWORD` | premier ADMIN créé par le seed | — / `admin` / — |
| `COMPANY_NAME` | nom initial de la société (modifiable ensuite par l'ADMIN) | `Ma Société` |
| `DEFAULT_ALERT_THRESHOLD` | seuil d'alerte des nouvelles lignes de stock | `5` |
| `TIMEZONE` | fuseau des statistiques par jour/mois et de l'année des numéros (ex. `Indian/Antananarivo`) | `UTC` |
| `DEMO_PASSWORD` | (développement) mot de passe des comptes créés par `python -m app.seed_demo` | — |
| `TEST_DATABASE_URL` | (tests) base de test, par défaut `DATABASE_URL` suffixée par `_test` | — |
| `INSTALL_DEV` | (build Docker) installe pytest dans l'image. Mettre `false` en production | `true` |

Pour générer un secret : `python -c "import secrets; print(secrets.token_urlsafe(48))"`.

---

## 4. Docker et PostgreSQL

```bash
docker compose up --build             # PostgreSQL + API (migrations et seed automatiques)
docker compose logs -f api            # logs de l'API
docker compose run --rm api pytest    # tests dans le conteneur
docker compose down                   # arrêt (les données restent dans le volume)
docker compose down -v                # arrêt ET suppression des données
```

- PostgreSQL 17 est exposé sur `localhost:5434`, pour ne pas gêner un PostgreSQL local.
- Les données sont dans le volume `postgres_data`.
- `scripts/entrypoint.sh` exécute `alembic upgrade head`, puis `python -m app.seed`, puis la commande du conteneur.

**Sans Docker**, avec un PostgreSQL déjà installé :

```bash
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
alembic upgrade head && python -m app.seed
uvicorn app.main:app --reload
```

---

## 5. Alembic (migrations)

Toute modification de la structure de la base passe par une migration. **Ne modifiez jamais le schéma de production à la main.**

```bash
alembic upgrade head                                 # appliquer les migrations
alembic revision --autogenerate -m "description"     # générer une migration après avoir modifié un modèle
alembic check                                        # vérifier que modèles et migrations sont alignés
alembic downgrade -1                                 # annuler la dernière migration
```

Migrations existantes :
1. `adb874fd17fe` : schéma initial.
2. `8732f6c28354` :
   - informations de la société, et copie de la société et du magasin sur chaque facture ;
   - prix de stock figé sur les lignes de vente ;
   - règle « prix de vente ≥ prix de stock » ;
   - révocation des jetons (`token_version`).

Points d'attention :
- **Relisez toujours** une migration générée.
- L'autogénération ne détecte ni les **séquences** (`invoice_number_seq`, `transfer_number_seq`) ni les **contraintes CHECK ajoutées** à une table existante : écrivez-les à la main, comme dans la migration 2.
- Les colonnes `UpperCaseString` s'écrivent `sa.String(...)` dans les migrations (voir `render_item` dans `alembic/env.py`).
- Les enums sont stockés en `VARCHAR` : ajouter une valeur, par exemple le paiement `MIXED`, ne demande pas de migration.
- Le test `app/tests/test_migrations.py` échoue si un modèle a changé sans migration.

---

## 6. Seed et premier ADMIN

```bash
python -m app.seed                          # hors Docker
docker compose exec api python -m app.seed  # avec Docker (déjà lancé automatiquement au démarrage)
```

Le seed est **idempotent** : on peut le relancer sans créer de doublons. Il crée ce qui manque :
1. les 44 permissions ;
2. les rôles **ADMIN** (toutes les permissions) et **VENDEUR**, avec leurs permissions par défaut (il n'en retire jamais) ;
3. le magasin **Stock Local** ;
4. la **société**, avec `COMPANY_NAME` ;
5. le **premier ADMIN**, à partir de `INITIAL_ADMIN_USERNAME`, `INITIAL_ADMIN_EMAIL` et `INITIAL_ADMIN_PASSWORD`. Il n'est créé que si ce nom d'utilisateur n'existe pas encore.

**Données de démonstration** (développement uniquement) :

```bash
python -m app.seed_demo   # nécessite DEMO_PASSWORD dans .env ; idempotent
```

Le script crée, s'ils n'existent pas :
- les ADMIN `valenciaraza@local.mg` et `antsa@local.mg` ;
- les magasins **H109** (Behoririka) et **C209** (La City) ;
- les vendeurs `vendeur1@local.mg` (H109), `vendeur2@local.mg` (C209) et `vendeur3@local.mg` (Stock Local) ;
- 10 produits de test approvisionnés dans le Stock Local.

Le mot de passe de ces comptes est `DEMO_PASSWORD` ; il n'est jamais écrit dans le code.

**Créer d'autres ADMIN** (co-administrateurs) : un ADMIN appelle `POST /api/v1/users` avec `"role": "ADMIN"`. Il n'existe pas de modèle « CoAdmin » : un co-administrateur est un utilisateur dont le rôle est ADMIN.

---

## 7. Utilisateurs, rôles et permissions

**Il n'existe que deux rôles.**

| Rôle | Périmètre | Permissions par défaut |
|---|---|---|
| **ADMIN** | tous les magasins (`store_id` peut rester `null`) | toutes |
| **VENDEUR** | uniquement son magasin (`User.store_id`) | `product.view`, `stock.view`, `store.stock.view`, `sale.view`, `sale.create`, `payment.view`, `payment.create`, `company.view`, `chat.view`, `chat.send` |

**Gestion des utilisateurs** (par un ADMIN) :

| Route | Action |
|---|---|
| `GET /users` | liste, avec les filtres `store_id`, `role=VENDEUR`, `is_active`, `search` |
| `POST /users` | créer un VENDEUR ou un ADMIN |
| `GET /users/{id}`, `PUT /users/{id}` | consulter, modifier les informations (et le mot de passe s'il est envoyé) |
| `PUT /users/{id}/role` | changer le rôle |
| `PUT /users/{id}/store` | affecter à un magasin, changer de magasin, ou retirer l'affectation (`null`) |
| `PUT /users/{id}/status` | activer ou désactiver le compte |
| `DELETE /users/{id}` | désactivation (l'historique est conservé) |
| `GET /stores/{id}/employees` | employés d'un magasin |

**Connexion** : `POST /auth/login` accepte le nom d'utilisateur **ou** l'email. Un changement de mot de passe révoque les jetons déjà émis (`TOKEN_REVOKED`).

**Garde-fous :**
- Seul un ADMIN peut attribuer le rôle ADMIN.
- Seul un ADMIN change l'affectation d'un utilisateur à un magasin.
- Un non-ADMIN qui aurait reçu des permissions `user.*` ne gère que les VENDEURS de son propre magasin.
- On ne peut pas se désactiver soi-même.
- Le **dernier ADMIN actif** ne peut être ni rétrogradé ni désactivé.

**Permissions.** Elles sont vérifiées par le backend sur chaque route : cacher un bouton dans le frontend ne protège rien. Les permissions d'un rôle se modifient avec `PUT /roles/{id}/permissions` (permission `permission.assign`). Le rôle ADMIN garde toujours `permission.view`, `permission.assign` et `role.view`.

Liste des permissions :
- `dashboard.view`, `report.view`, `audit.view`
- `user.view` / `create` / `update` / `delete`
- `role.view` / `update`, `permission.view` / `assign`
  - `role.create` et `role.delete` existent mais sont réservées : il n'y a que deux rôles fixes.
- `store.view` / `create` / `update` / `delete`, `store.stock.view`
- `store.transfer.create` / `view` / `cancel`, et `stock.transfer` (équivalent de `store.transfer.create`)
- `product.view` / `create` / `update` / `delete` (elles couvrent aussi les catégories)
- `stock.view` / `entry` / `exit` / `adjust` (l'ajustement couvre aussi les seuils)
- `sale.view` / `create` / `cancel` / `discount`
  - `sale.view` et `sale.create` couvrent aussi les clients et les factures.
- `payment.view` / `create`
- `cash.view` / `open` / `close` / `transaction`
- `company.view` / `update`
- `chat.view` / `send`

**Isolation des magasins (règle critique).** Le magasin d'un VENDEUR vient toujours de `current_user.store_id`. S'il envoie le `store_id` d'un autre magasin, la requête est refusée (`403 INVALID_STORE_ACCESS`) pour les ventes, le stock, les mouvements, la caisse, l'historique, les rapports, les clients et les dettes. Un VENDEUR sans magasin ne peut réaliser aucune opération de magasin. La règle est centralisée dans `services/store_access.py`.

---

## 8. Magasins et Stock Local

- Un magasin se **crée sans vendeur** (`POST /stores`) ; les vendeurs y sont affectés ensuite (`PUT /users/{id}/store`).
- Le **Stock Local** est créé par le seed (`is_central = true`). C'est le stock central qui alimente les autres magasins. Il n'a pas besoin de vendeurs. Il ne peut être ni supprimé ni désactivé.
- Un ADMIN qui ne précise pas de magasin travaille dans le Stock Local.
- La suppression d'un magasin est une désactivation : son historique et son stock sont conservés.

---

## 9. Produits, stocks et seuils

**Produits.**
- `reference` et `name` ne sont **pas uniques** : seul `id` identifie un produit.
- Règle : **prix de vente ≥ prix de stock** (`selling_price >= purchase_price`). Elle est vérifiée par le schéma (422), par le service à la création et à la modification (400 `INVALID_SELLING_PRICE`, même si un seul prix est envoyé) et par une contrainte en base.
- `unit_profit` = prix de vente − prix de stock.
- Le produit n'a pas de champ stock. À sa création, une ligne de stock à 0 est créée dans le Stock Local.

**Stock par magasin** : table `stocks`, une ligne par couple (produit, magasin), `UNIQUE(product_id, store_id)`, quantité jamais négative.

| Champ calculé (jamais stocké) | Définition |
|---|---|
| `low_stock` | 0 < quantité ≤ `alert_threshold` |
| `out_of_stock` | quantité = 0 dans ce magasin |
| `purchase_value` | quantité × prix de stock |
| `sale_value` | quantité × prix de vente |
| `potential_profit` | `sale_value` − `purchase_value` |

| Route | Usage |
|---|---|
| `GET /stock` | toutes les lignes, avec les filtres `store_id`, `product_id`, `low_stock`, `out_of_stock`, `search` |
| `GET /stock/{id}`, `GET /stock/store/{store_id}` | une ligne, le stock d'un magasin |
| `GET /stock/low-stock`, `GET /stock/out-of-stock` | lignes en alerte |
| `POST /stock/entry` | entrée de stock (crée la ligne si besoin) |
| `POST /stock/exit` | sortie (`EXIT`) ou perte (`LOSS`) |
| `POST /stock/adjust` | ajustement d'inventaire |
| `PUT /stock/{id}/alert-threshold` | modifier le seuil d'une ligne |
| `GET /stock/movements` | historique des mouvements |

Chaque variation crée un **mouvement** (`ENTRY`, `EXIT`, `SALE`, `RETURN`, `ADJUSTMENT`, `LOSS`, `TRANSFER_OUT`, `TRANSFER_IN`). Il garde l'utilisateur, le magasin, le produit, la quantité signée, la date, le motif et la référence.

---

## 10. Transferts

`POST /api/v1/stock-transfers` :

```json
{"source_store_id": 1, "destination_store_id": 2, "items": [{"product_id": 10, "quantity": 5}]}
```

| Stock source | Transfert | Résultat |
|---|---|---|
| 10 | 5 | source 5, destination 5 (ligne créée si la destination n'avait pas le produit) |
| 10 | 10 | source **0 (stock déplacé, pas perdu)**, destination 10 |
| 10 | 11 | **refusé** (`INSUFFICIENT_STOCK`), rien n'est modifié |

**Règles :**
- La source doit être différente de la destination.
- Les quantités sont strictement positives ; plusieurs produits sont possibles dans un même transfert.
- La source par défaut est le Stock Local (ADMIN) ou le magasin du vendeur.
- Un transfert **n'est ni une vente ni une perte**, et le **stock global ne change pas**.

**Fonctionnement :**
- Le transfert est **atomique** : verrouillage `SELECT … FOR UPDATE` des lignes concernées, mouvements `TRANSFER_OUT` / `TRANSFER_IN`, référence `TRF-AAAA-NNNNNN`, audit, le tout dans une seule transaction.
- Si deux transferts de 4 partent en même temps sur un stock de 5, un seul réussit (test `test_concurrency.py`).
- `POST /stock-transfers/{id}/cancel` renvoie le stock vers la source. C'est impossible si la destination ne l'a plus.

---

## 11. Clients, ventes, paiements et dettes

**Clients** : nom, prénom, téléphone.

| Route | Usage |
|---|---|
| `GET /customers` | recherche avec `search` / `phone`, filtres `has_debt` / `store_id` |
| `GET /customers/contacts` | totaux d'achats, montant payé, reste dû, dernier achat |
| `GET /customers/{id}/sales` | historique d'achats |
| `GET /customers/{id}/debts` | ventes non soldées et dette totale |

Le répertoire des clients est commun à tous les magasins, mais un VENDEUR ne voit que les achats et les dettes de son magasin.

**Vente** (`POST /api/v1/sales`), en une seule transaction :
1. auth et permission ;
2. magasin (celui du vendeur) ;
3. client ;
4. verrouillage et vérification des stocks ;
5. sous-total, remise et total, **calculés par le serveur** ;
6. Sale et SaleItems ;
7. déduction du stock et mouvements `SALE` ;
8. paiement initial, puis caisse si le paiement est en espèces ;
9. audit, puis COMMIT.

En cas d'erreur, tout est annulé (**ROLLBACK**).

```json
{
  "customer": {"first_name": "Jean", "last_name": "Rakoto", "phone": "0341234567"},
  "items": [{"product_id": 1, "quantity": 2}, {"product_id": 2, "quantity": 1}],
  "discount_type": "FIXED",
  "discount_value": 5000,
  "payment": {"method": "CASH", "amount": 20000},
  "payment_due_date": "2026-10-15"
}
```

**Règles de la vente :**
- `sale.user_id` est **toujours l'utilisateur connecté** (lu dans le JWT) et `sale.store_id` est son magasin. Le frontend ne peut pas les choisir.
- Client : `customer_id` (client existant) ou `customer` (nouveau, réutilisé s'il existe déjà à l'identique).
- Remise : `NONE`, `PERCENTAGE` (≤ 100) ou `FIXED` (≤ sous-total). Elle nécessite la permission `sale.discount`.
- `SaleItem` conserve la référence, le nom, le **prix unitaire appliqué** et le prix de stock du moment : la facture et le bénéfice ne changent pas si le produit est modifié ensuite.
- Toutes les vérifications sont faites avant de tirer le numéro de facture : une vente refusée ne consomme pas de numéro.

**Paiements.** Une ligne `Payment` est une somme réellement encaissée (montant > 0). L'historique n'est jamais écrasé.

| `payment` envoyé | Résultat |
|---|---|
| `{"method": "CASH"}` (sans montant) | paiement complet → `PAID` |
| `{"method": "CASH", "amount": 10000}` sur 20 000 | avance → `PARTIAL`, reste 10 000 |
| absent, ou `{"method": "CREDIT"}` | rien n'est encaissé → `UNPAID` |

**Avance et dette :**
- S'il reste un montant dû, le **téléphone du client** et la **date d'échéance** (`payment_due_date`) sont obligatoires.
- Pour un paiement complet, l'échéance est ignorée.
- Quand le client revient, `POST /api/v1/payments` (`sale_id`, `method`, `amount`) enregistre le paiement. Le statut passe à `PARTIAL` puis `PAID`.
- Sont interdits : un **surpaiement**, un paiement sur une vente déjà **PAID** (`PAYMENT_ALREADY_COMPLETED`) et un paiement sur une vente annulée.

`amount_paid` (somme des paiements) et `remaining_amount` (total − payé) sont toujours calculés par le backend.

Le mode `MIXED` n'est pas implémenté. L'architecture est prête : une vente accepte plusieurs paiements, chacun enregistré par `payment_service.record_payment()`.

**Historique** : `GET /sales/history`.
- Recherche (`search`) par n° de facture, nom, prénom ou téléphone.
- Filtres : `user_id`, `store_id`, `customer_id`, `payment_status`, `has_debt`, `status`, `date_from`, `date_to`.
- Chaque ligne affiche la facture, le client, son téléphone, l'utilisateur et son rôle, le magasin, la date, le total, le montant payé, le reste dû et le statut.
- Voir aussi `GET /sales/{id}` et `GET /sales/{id}/payments`.

**Annulation** : `POST /sales/{id}/cancel` (permission `sale.cancel`).
- Le stock est remis dans le magasin (mouvements `RETURN`).
- Les espèces sont remboursées depuis la caisse ouverte.
- L'opération est auditée.
- Une deuxième annulation renvoie `SALE_ALREADY_CANCELLED`.

---

## 12. Société et factures

**Société** (`GET` / `PUT /api/v1/company`) : une seule configuration (nom, logo, téléphone, email, adresse, ville).
- Seul l'ADMIN peut la modifier (`company.update`). Chaque modification est auditée, avec l'ancienne et la nouvelle valeur.
- Le logo n'est **pas stocké dans PostgreSQL** : `logo_url` contient une adresse web (`https://…`) ou un chemin (`/media/logo.png`). On le remplace en envoyant une autre valeur.

**Facture** (`GET /api/v1/sales/{id}/invoice`). Elle contient :
- **la société** : logo, nom, adresse, ville, téléphone, email ;
- **la facture** : numéro `FAC-AAAA-NNNNNN`, date et heure, magasin, vendeur et son rôle ;
- **le client** : nom, prénom, téléphone ;
- **les lignes** : référence, nom, quantité, prix unitaire, total ;
- **les montants** : sous-total, remise, total, paiements, montant payé, reste dû, statut, échéance ;
- **un message de remerciement** construit avec le nom de la société de la facture (`["Merci pour votre achat !", "À bientôt chez allsafe."]`).

**Fidélité historique.**
- À chaque vente, les informations de la société **et du magasin** sont **copiées** (`InvoiceCompanySnapshot`). Si l'ADMIN change ensuite le nom, le logo ou l'adresse, ou renomme le magasin, les anciennes factures gardent les anciennes informations ; les nouvelles utilisent les nouvelles.
- De même, les factures gardent le prix et le nom des produits au moment de la vente.

---

## 13. Caisse

- Une seule caisse ouverte par magasin (`POST /cash/registers/open`, `POST /cash/registers/{id}/close`).
- Chaque **paiement en espèces** (vente, avance ou solde de dette) crée une opération `SALE` dans la caisse ouverte du magasin. Un paiement en espèces est refusé si aucune caisse n'est ouverte (`CASH_REGISTER_CLOSED`).
- **Exemple** : une vente de 20 000 payée par une avance de 10 000 le jour 1, puis 10 000 le jour 2. Le chiffre d'affaires est de 20 000 et la caisse reçoit 10 000 puis 10 000.
- Opérations manuelles : `EXPENSE`, `WITHDRAWAL`, `DEPOSIT`, `ADJUSTMENT`. `REFUND` est créée automatiquement à l'annulation d'une vente.
- `expected_amount` est mis à jour à chaque opération et ne devient jamais négatif. À la clôture : `difference = closing_amount − expected_amount`.
- Par défaut, seul l'ADMIN gère la caisse. Il peut donner `cash.*` au rôle VENDEUR.

---

## 14. Tableau de bord

Il n'y a pas de table Dashboard : tout est calculé à partir des données existantes. Filtres : `store_id`, `date_from`, `date_to`.

| Route | Contenu |
|---|---|
| `GET /dashboard/summary` | ventes, chiffre d'affaires, bénéfice (au prix de stock du moment de la vente), encaissements, dettes, produits, magasins, stock, `low_stock_count`, `out_of_stock_count` (à zéro dans un magasin), `unavailable_products_count` (à zéro **dans tous** les magasins), meilleurs produits, ventes récentes |
| `GET /dashboard/sales` | ventes par jour ou par mois |
| `GET /dashboard/top-products` | produits les plus vendus |
| `GET /dashboard/low-stock` | lignes de stock en alerte |
| `GET /dashboard/stock-value` | valeur au prix de stock, valeur de vente et bénéfice potentiel, **par magasin et au global** (`?product_id=` pour un produit) |

Les transferts ne comptent jamais comme vente, perte ou dépense.

---

## 15. Audit

`GET /api/v1/audit` (permission `audit.view`), filtrable par utilisateur, action, type d'entité et période. Chaque entrée garde l'utilisateur, l'action, l'ancienne et la nouvelle valeur, l'adresse IP et la date.

Sont tracés :
- la connexion, réussie ou non ;
- les utilisateurs (création, modification, rôle, magasin, statut) ;
- les magasins, catégories et produits ;
- les mouvements de stock et les seuils ;
- les transferts ;
- les clients ;
- les ventes, remises et annulations ;
- les paiements ;
- la caisse ;
- les permissions ;
- la société.

Ne sont **jamais** enregistrés : mots de passe, `password_hash`, jetons JWT, secrets.

---

## 16. Tests

```bash
docker compose up -d postgres && pytest   # en local
docker compose run --rm api pytest        # dans Docker
```

- Les tests utilisent une base dédiée (`<base>_test`), **reconstruite par les migrations** à chaque session.
- Chaque test s'annule à la fin (transaction + savepoints).
- `app/tests/factories.py` crée rapidement magasins, produits, utilisateurs, clients et caisses.

| Fichier | Couverture |
|---|---|
| `test_auth.py` | login, refresh, `/me`, utilisateur inactif, jetons invalides |
| `test_users.py` | création, plusieurs ADMIN, modification, rôle, affectation et changement de magasin, statut, dernier ADMIN |
| `test_rbac.py` | permissions ADMIN / VENDEUR, attribution des permissions, isolation des magasins |
| `test_stores.py`, `test_products.py`, `test_prices.py` | magasins, Stock Local, CRUD produits, références et noms identiques autorisés, règle de prix, valeurs du stock |
| `test_stock.py`, `test_transfers.py` | entrées, sorties, ajustements, seuils, transferts (10→5, 10→10, 10→11, rollback, stock global), annulation |
| `test_customers.py`, `test_sales.py`, `test_discounts.py` | clients, contacts, dettes, ventes, utilisateur connecté, snapshot, remises, rollback, annulation, historique |
| `test_payments.py`, `test_cash.py` | paiement complet, avance, dette, échéance, paiements multiples, surpaiement, caisse |
| `test_company.py`, `test_invoices.py` | société, contenu de la facture, fidélité historique (société, produits, prix) |
| `test_dashboard.py`, `test_audit.py`, `test_chat.py` | statistiques, audit, messagerie |
| `test_concurrency.py` | ventes et transferts simultanés réels : jamais de survente ni de stock négatif |
| `test_review_fixes.py` | garde-fous issus de la revue : gestion déléguée des utilisateurs, annulation de transfert, révocation des jetons, historique, numérotation |
| `test_seed_demo.py` | données de démonstration idempotentes, connexion par email |
| `test_migrations.py`, `test_docs.py` | modèles alignés avec les migrations, routes versionnées et documentées |

---

## 17. Documentation de l'API (Swagger, ReDoc)

- **Swagger UI** : `/docs`. Connectez-vous avec `POST /api/v1/auth/login`, puis utilisez **Authorize**.
- **ReDoc** : `/redoc`
- **OpenAPI** : `/openapi.json`

Toutes les routes commencent par `/api/v1/`. Chacune a un résumé, une description, un modèle de réponse et ses erreurs possibles.

Format commun :
- Erreurs : `{"detail": "message lisible", "code": "CODE_MACHINE"}`. En 422, une liste `errors` est ajoutée, avec une entrée par champ.
- Listes : `page`, `page_size` (≤ 100) et `sort` (`name` ou `-created_at`). La réponse contient `items`, `total`, `page`, `page_size` et `pages`.

---

## 18. Conventions de code

- **Routes** : HTTP uniquement. **Services** : toute la logique métier. **Modèles** : SQLAlchemy et relations.
- **Transactions** : chaque service d'écriture se termine par `db.commit()`. Toute exception levée avant entraîne un ROLLBACK (`core/database.py`).
- **Exceptions métier nommées** (`core/exceptions.py`) :
  - `ProductNotFound`, `StoreNotFound`, `CustomerNotFound`, `UserNotFound` ;
  - `InsufficientStock`, `InactiveProduct`, `InactiveStore`, `InvalidTransfer` ;
  - `CashRegisterClosed`, `SaleAlreadyCancelled`, `PaymentAlreadyCompleted` ;
  - `InvalidPayment`, `InvalidDiscount`, `InvalidSellingPrice` ;
  - `PermissionDenied`, `InvalidStoreAccess`.
- **Montants** : `Numeric(14, 2)` en base, `Decimal` en Python, nombre dans le JSON. L'arrondi est commercial, au centime.
- **Textes métier** (noms, références, descriptions, adresses) :
  - ils sont enregistrés en MAJUSCULES et renvoyés en minuscules (`UpperStr`, `UpperCaseString`, `DisplayStr`) ; les recherches sont donc insensibles à la casse ;
  - exceptions : emails, mots de passe, téléphones, URL du logo, contenu du chat, codes (rôles `ADMIN` / `VENDEUR`, numéros `FAC-…` / `TRF-…`, références de paiement et de mouvement, enums).
- **Temps réel** : la V1 fonctionne en HTTP. Les services (`chat_service.send_message`, ventes, stock, paiements) sont réutilisables tels quels par un futur endpoint WebSocket ou un système de notifications.
