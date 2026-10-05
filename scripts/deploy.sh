#!/usr/bin/env bash
# Déploie l'API sur le VPS : copie du code puis (re)démarrage de la stack Docker.
#
#   VPS_HOST=185.215.167.79 VPS_USER=smart SSH_KEY=~/.ssh/valperso_deploy scripts/deploy.sh
#
# Variables : VPS_HOST, VPS_USER (obligatoires), VPS_PATH (défaut : valperso, dans le dossier
# personnel), SSH_KEY (clé privée), API_PORT (port public de l'API, défaut : 8020).
# Utilisé aussi par la CI/CD GitHub Actions (.github/workflows/ci-cd.yml).
set -euo pipefail
cd "$(dirname "$0")/.."

: "${VPS_HOST:?VPS_HOST manquant}"
: "${VPS_USER:?VPS_USER manquant}"
VPS_PATH="${VPS_PATH:-valperso}"
TARGET="$VPS_USER@$VPS_HOST"
SSH_OPTS=(-o ConnectTimeout=20)
if [[ -n "${SSH_KEY:-}" ]]; then
  SSH_OPTS+=(-i "$SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes)
fi

echo "==> Copie du code vers $TARGET:$VPS_PATH"
# Seul le backend part sur le serveur : l'application Flutter n'y est pas utilisée.
tar --exclude=./.env --exclude=./.venv --exclude=./.git --exclude=./frontend --exclude=./backups \
  --exclude=./media --exclude='__pycache__' --exclude=.pytest_cache --exclude=.ruff_cache \
  -czf - . | ssh "${SSH_OPTS[@]}" "$TARGET" "cat > valperso-release.tgz"

echo "==> Démarrage de la stack"
ssh "${SSH_OPTS[@]}" "$TARGET" bash -s -- "$VPS_PATH" <<'REMOTE'
set -euo pipefail
mkdir -p "$1"
cd "$1"
# Remplace tout le code sauf le .env : un fichier supprimé du dépôt (une migration par exemple)
# ne doit pas rester sur le serveur. Les données sont dans les volumes Docker, pas ici.
find . -mindepth 1 -maxdepth 1 ! -name .env -exec rm -rf {} +
tar -xzf ~/valperso-release.tgz
rm -f ~/valperso-release.tgz
if [ ! -f .env ]; then
  echo "ERREUR : $PWD/.env manquant. Le créer une fois sur le serveur (voir DEPLOYMENT.md)." >&2
  exit 1
fi
# dc() ajoute "< /dev/null" : sans cela, docker compose lirait la suite du script sur l'entrée standard.
dc() { docker compose -f docker-compose.yml -f docker-compose.prod.yml "$@" < /dev/null; }
dc up -d --build --wait --wait-timeout 180 --remove-orphans
docker image prune -f > /dev/null < /dev/null
dc ps
REMOTE

echo "==> Vérification"
curl --fail --silent --show-error --max-time 20 "http://$VPS_HOST:${API_PORT:-8020}/api/v1/health"
echo
