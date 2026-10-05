# Déploiement (VPS) et CI/CD GitHub Actions

## En production

```
Internet ──▶ API :8020  (http://185.215.167.79:8020)
             PostgreSQL : réseau Docker uniquement, jamais publié
```

- Serveur : `smart@185.215.167.79` (Ubuntu 24.04), dossier `~/valperso`.
- Seul le backend est déployé. Les applications Flutter (Android, Linux) s'y connectent :
  adresse du serveur `http://185.215.167.79:8020` (lien « Serveur : … » sous le formulaire de
  connexion, ou Paramètres → Serveur), ou au build : `--dart-define=API_URL=http://185.215.167.79:8020`.
- Pas de reverse proxy : comme les autres applications du VPS, l'API a son propre port. Les ports
  3000, 3010, 5678, 8000 et 8010 appartiennent à d'autres applications (`smart_*`, `garrix-offre`).
- `docker-compose.prod.yml` (surcharge) : PostgreSQL non publié, image sans pytest
  (`INSTALL_DEV=false`), healthcheck de l'API, redémarrage automatique, logs limités.
- Au démarrage, le conteneur applique les migrations Alembic puis le seed (idempotent).

URLs : `/api/v1/health`, `/docs` (Swagger), `/redoc`, `/api/v1/...`, `/media/...`.

## Le `.env` du serveur

Il n'existe que sur le serveur (`~/valperso/.env`), n'est jamais versionné ni copié par le
déploiement. Valeurs propres à la production :

| Variable | Valeur |
|---|---|
| `APP_ENV` | `production` (l'API refuse alors un `JWT_SECRET_KEY` de moins de 32 caractères) |
| `API_PORT` | `8020` |
| `POSTGRES_PASSWORD`, `JWT_SECRET_KEY`, `INITIAL_ADMIN_PASSWORD` | générés aléatoirement sur le serveur |
| `CORS_ORIGINS` | vide (les applications natives n'en ont pas besoin) |
| `INSTALL_DEV` | `false` |
| `TIMEZONE` | `Indian/Antananarivo` |

Après une modification du `.env` : `dc up -d` (voir plus bas).

## Déploiement manuel

```bash
VPS_HOST=185.215.167.79 VPS_USER=smart SSH_KEY=~/.ssh/valperso_deploy scripts/deploy.sh
```

`scripts/deploy.sh` copie le backend (sans `.env`, `frontend`, `.git`), remplace l'ancien code
du serveur, lance `docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
--wait`, puis vérifie `/api/v1/health`.

## CI/CD GitHub Actions

Le workflow `.github/workflows/ci-cd.yml` :

| Job | Quand | Rôle |
|---|---|---|
| `backend` | push et pull request | Ruff, pytest (PostgreSQL 17 en service) |
| `frontend` | push et pull request | `flutter analyze`, `flutter test --exclude-tags visual` |
| `docker` | push et pull request | construction de l'image de production de l'API |
| `deploy` | push sur `main` (ou lancement manuel) | `scripts/deploy.sh` vers le VPS, après `backend` et `docker` |

Les captures de référence (`test/visual`, tag `visual`) dépendent des polices installées sur le
poste : elles restent à lancer en local (`flutter test`).

### Clé SSH de déploiement (une fois, sur votre poste)

```bash
ssh-keygen -t ed25519 -N "" -C github-actions-valperso -f ~/.ssh/valperso_deploy
ssh-copy-id -i ~/.ssh/valperso_deploy.pub smart@185.215.167.79
ssh -i ~/.ssh/valperso_deploy smart@185.215.167.79 echo ok    # doit répondre sans mot de passe
```

### Secrets à créer

GitHub → dépôt → **Settings → Secrets and variables → Actions → New repository secret** :

| Nom | Valeur |
|---|---|
| `VPS_HOST` | `185.215.167.79` |
| `VPS_USER` | `smart` |
| `VPS_SSH_KEY` | contenu **complet** de `~/.ssh/valperso_deploy` (de `-----BEGIN OPENSSH PRIVATE KEY-----` à `-----END OPENSSH PRIVATE KEY-----`) |
| `VPS_KNOWN_HOSTS` | `185.215.167.79 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN9TJehy4dCeucS45PxCCaek/kbPo/pxwnjLCUclkCJb` |

`VPS_KNOWN_HOSTS` empêche une usurpation du serveur (vérifiable avec
`ssh-keyscan -t ed25519 185.215.167.79`).

Variables optionnelles (onglet **Variables**) : `VPS_PATH` (défaut `valperso`), `API_PORT`
(défaut `8020`, port vérifié après le déploiement).

Le job `deploy` utilise l'environnement GitHub `production` : dans **Settings → Environments →
production**, vous pouvez exiger une validation manuelle avant chaque déploiement.

## Exploitation

```bash
ssh smart@185.215.167.79
cd ~/valperso
alias dc='docker compose -f docker-compose.yml -f docker-compose.prod.yml'   # toujours les 2 fichiers

dc ps                      # état (api doit être "healthy")
dc logs -f api             # logs ; Ctrl+C pour quitter
dc up -d                   # appliquer une modification du .env
dc restart api             # redémarrer l'API
dc exec -T postgres pg_dump -U commerce commerce > sauvegarde_$(date +%F).sql   # sauvegarde
```

Ne lancez jamais `dc down -v` : cela supprime les volumes, donc la base et les photos.

Console SQL (sur le serveur) : `dc exec postgres psql -U commerce commerce`.

## À faire

1. **Changer le mot de passe de l'ADMIN** après la première connexion.
2. **Sécurité SSH** : changer le mot de passe du compte `smart` (`passwd`), puis désactiver la
   connexion SSH par mot de passe une fois les clés en place.
3. **HTTPS** : faire pointer un nom de domaine vers le serveur, puis ajouter un certificat
   (Caddy ou Certbot en frontal). Sans HTTPS, les jetons circulent en clair sur le réseau.
