#!/bin/sh
# Applique les migrations et les données initiales (idempotent), puis lance la commande demandée.
set -e

alembic upgrade head
python -m app.seed

exec "$@"
