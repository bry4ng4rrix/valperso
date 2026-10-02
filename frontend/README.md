# Bryan Garrix — application Flutter

Application cliente de l'API FastAPI du dossier parent (gestion commerciale multi-magasins).

- **Plateformes** : Android (prioritaire) et Linux (bureau). Pas d'iOS.
- **Thème** : sombre par défaut, entièrement noir et gris neutres (actions principales en blanc, couleurs réservées aux états : vert payé, orange alerte, rouge dette), Material 3. Thème clair (actions en bleu) disponible dans Paramètres.
- **Écrans adaptatifs** : mobile < 600 px (barre de navigation en bas : Accueil, Ventes, Produits, Clients, Plus), tablette 600–1024 px (menu latéral compact), bureau > 1024 px (menu latéral complet). Les boîtes de dialogue ont une largeur fixe adaptée à l'écran (presque toute la largeur sur mobile), un contenu qui défile et des boutons toujours visibles.
- Le backend n'est pas modifié : l'application utilise uniquement les routes `/api/v1` existantes.

## Démarrage

Prérequis : Flutter 3.44 ou plus récent (Dart 3.12).

```bash
cd frontend
flutter pub get

# Linux : API Docker locale sur le port 8001 (adresse par défaut, rien à préciser)
flutter run -d linux

# Émulateur Android : http://10.0.2.2:8001 par défaut (10.0.2.2 = la machine hôte)
flutter run -d emulator-5554

# Téléphone sur le réseau local : adresse IP de l'ordinateur qui fait tourner l'API
flutter run --dart-define=API_URL=http://192.168.1.10:8001
```

L'adresse du serveur peut aussi être changée dans l'application : lien « Serveur : … » sous le formulaire de connexion, ou Paramètres → Serveur. L'adresse est testée (`/api/v1/health`) avant d'être enregistrée.

Ordre de priorité de l'adresse : valeur enregistrée dans l'application, puis `--dart-define=API_URL`, puis `http://10.0.2.2:8001` (Android) / `http://localhost:8001` (Linux).

**Linux** : le stockage sécurisé des jetons utilise libsecret (`libsecret-1-0` et un trousseau, par exemple gnome-keyring). Pour compiler : `libgtk-3-dev` et `libsecret-1-dev`.

**Android** : `android:usesCleartextTraffic="true"` permet d'utiliser l'API en HTTP sur le réseau local. En production, servir l'API en HTTPS et retirer cette option.

Comptes de démonstration : voir le README du backend (`python -m app.seed_demo`, mot de passe défini par `DEMO_PASSWORD`). La connexion accepte le nom d'utilisateur ou l'email.

## Architecture

```
lib/
  app/        application, routeur (go_router), navigation par permissions, shell responsive, thème
  core/       client API (dio), erreurs, session, stockage sécurisé, export Excel, formats, confirmations
  shared/     widgets réutilisables (listes paginées, filtres, boutons, cartes, badges…), validateurs
  features/   un dossier par domaine : modèles + repository + écrans
```

- **Gestion d'état** : `provider` + `ChangeNotifier`, et rien d'autre (session, paramètres, panier, listes paginées).
- **Client API** : un seul `ApiClient` gère l'adresse, le préfixe `/api/v1`, les délais, l'ajout du jeton, le renouvellement automatique sur 401 (une seule fois, requêtes en file d'attente), le retour au login si la session ne peut pas être renouvelée, et la conversion des erreurs en messages français (`ApiException`). Les erreurs de validation (422) s'affichent sous le champ concerné.
- **Sécurité** : seuls les jetons sont stockés (flutter_secure_storage), jamais le mot de passe. Les menus et routes sont filtrés selon les permissions de `/auth/me`. Le backend reste la référence pour les droits.
- **Textes** : l'API renvoie les noms en minuscules ; l'affichage remet les majuscules (`Formats.capitalize` / `Formats.title`). Le magasin central s'affiche toujours « Stock Local ».

## Fonctionnalités

| Écran | Contenu |
| --- | --- |
| Connexion | identifiant ou email, mot de passe, adresse du serveur, message si la session a expiré |
| Accueil | ADMIN : tableau de bord (périodes Aujourd'hui → Personnalisé, magasin, indicateurs, actions rapides, évolution des ventes, meilleures ventes, dernières ventes, stocks à surveiller). VENDEUR : ventes du jour, actions rapides, alertes de stock de son magasin |
| Ventes | un seul écran avec deux onglets, « Nouvelle vente » et « Historique » (le panier et la recherche sont conservés d'un onglet à l'autre) |
| Nouvelle vente | mobile en 4 étapes (Produits → Client → Paiement → Résumé), bureau en deux panneaux ; stock disponible par magasin, client existant ou nouveau, paiement « Payé » ou « Dette (avance) » sans choix du mode de paiement (champ pré-rempli avec le total, vide = dette sans avance), échéancier (une ou plusieurs dates de remboursement, reste réparti également, montants modifiables) et téléphone exigés s'il reste un montant, description par article (taille, couleur...) ; **confirmation avant l'envoi, un seul envoi** ; écran final : facture, partage, nouvelle vente |
| Historique des ventes | période, recherche (n° de facture, client, téléphone), filtres, tri, cartes ou tableau, export |
| Détail de vente | articles (avec description), montants, échéancier (payé, reste, à payer, en retard), paiements, encaisser, annuler (motif + double confirmation), facture |
| Facture | aperçu, PDF partagé (Android) ou enregistré (Linux) ; informations de la société figées au moment de la vente |
| Produits | par magasin (quantité, état) ou catalogue, cartes avec prix, marge et état, fiche (stock par magasin, stock global, mouvements), formulaire (prix de vente ≥ prix d'achat), désactivation |
| Mouvements | historique des mouvements (type « Transfert » avec magasins d'origine et de destination), opérations (entrée, sortie, perte, ajustement) confirmées avec quantité avant → après ; le stock par magasin se consulte dans Produits |
| Transferts | liste, nouveau transfert (magasins → produits → quantités → récapitulatif → confirmation → stocks des deux magasins), annulation |
| Clients | tous / avec dette, fiche avec dettes (encaisser) et achats, création |
| Paiements et dettes | paiements reçus, ventes avec reste à payer |
| Magasins, Utilisateurs, Catégories | listes, fiches, formulaires ; changements de rôle, de magasin et de statut confirmés (avant → après) |
| Paramètres | profil, thème, serveur, société (modification avec liste des changements), rôles et permissions, déconnexion confirmée |
| Journal d'audit, Messages | journal filtrable avec détail avant / après ; conversations privées et de groupe |

Toutes les listes ont : recherche (avec délai), filtres (feuille en bas sur mobile, boîte de dialogue sur grand écran), tri, pagination serveur (`page_size` ≤ 100), états chargement / vide / erreur, tirer pour actualiser, et un export Excel « résultats filtrés » ou « tout ».

## Tests

Aucune compilation (APK, Linux) n'est nécessaire pour vérifier l'application :

```bash
flutter analyze      # aucune remarque
flutter test         # 87 tests ; les tests « API réelle » sont ignorés sans LIVE_API_URL
```

- `test/core`, `test/app`, `test/features/cart_controller_test.dart` : client API (jeton, renouvellement, expiration), erreurs, formats, périodes, liste paginée, export Excel, panier (calculs identiques au serveur), navigation et garde des routes.
- `test/widgets` : boîte de confirmation (normale, double confirmation, motif obligatoire), bouton anti double envoi.
- `test/app/login_and_shell_test.dart` : connexion, erreurs, barre du bas / menu latéral selon les permissions, déconnexion, session expirée.
- `test/features/new_sale_flow_test.dart` : vente complète (aucun envoi avant confirmation, un seul POST), avance sans téléphone bloquée, vente refusée (panier conservé), dette sans avance, étapes mobiles.
- `test/features/management_flows_test.dart` : règle de prix, modification avec différences, transfert, changement de rôle, transferts dans les mouvements (source → destination), entrée de stock.
- `test/app/screens_smoke_test.dart` : les 35 écrans sur ordinateur, tablette, mobile et petit téléphone (360 px), sans erreur ni débordement ; écrans du vendeur ; routes interdites.
- `test/live/api_live_test.dart` : parcours contre la vraie API, **sur une base dédiée** :

```bash
# depuis la racine du projet, avec PostgreSQL du docker-compose (port 5434)
docker exec valperso-postgres-1 psql -U commerce -d postgres -c "CREATE DATABASE commerce_e2e;"
export DATABASE_URL=postgresql+psycopg://commerce:commerce@localhost:5434/commerce_e2e DEMO_PASSWORD=<mot de passe de test>
.venv/bin/alembic upgrade head && .venv/bin/python -m app.seed && .venv/bin/python -m app.seed_demo
.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8002 &
cd frontend && LIVE_API_URL=http://127.0.0.1:8002 LIVE_PASSWORD=<mot de passe de test> flutter test test/live
# puis arrêter uvicorn et supprimer la base : DROP DATABASE commerce_e2e WITH (FORCE);
```

## Compilation (quand nécessaire)

```bash
flutter build apk --release --dart-define=API_URL=https://api.exemple.mg
flutter build linux --release --dart-define=API_URL=https://api.exemple.mg
```

## Limites connues (liées à l'API actuelle)

- **Images de produit** : l'API n'a pas encore de route d'image ; une vignette avec l'initiale est affichée. Le modèle lit déjà `image_url`, et `ProductAvatar` l'affichera dès que l'API le fournira (jusqu'à 10 images prévues par la spécification).
- **Export** : l'API n'a pas de route d'export ; le fichier Excel est construit dans l'application en parcourant toutes les pages (100 lignes par requête) avec les filtres affichés.
- **Impression** : pas de paquet d'impression (pour limiter les dépendances) ; sur Android, le menu de partage du PDF permet d'imprimer, sur Linux le PDF est enregistré dans Téléchargements.
- **Messages** : pas de temps réel côté API ; les conversations sont actualisées toutes les 10 à 20 secondes quand l'écran est ouvert.
- **Logo de la société** : adresse web ou chemin servi par le serveur (`/media/...`) ; le téléversement de fichier n'existe pas dans l'API.
