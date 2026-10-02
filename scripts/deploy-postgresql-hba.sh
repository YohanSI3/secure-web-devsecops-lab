#!/usr/bin/env bash
# Déploie postgresql/pg_hba.conf (versionné dans ce dépôt) vers
# /etc/postgresql/<version>/main/pg_hba.conf -- même logique que
# scripts/deploy-nginx-config.sh : fichier source dans le dépôt, copié (pas
# symlinké -- un service qui recharge sa config attend un fichier dont le
# propriétaire/permissions sont corrects, pas un lien vers un fichier
# possédé par l'utilisateur courant), puis rechargement du service.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${REPO_ROOT}/postgresql/pg_hba.conf"
PG_VERSION_DIR="$(ls /etc/postgresql/)"
DEST="/etc/postgresql/${PG_VERSION_DIR}/main/pg_hba.conf"

sudo cp "$SRC" "$DEST"
sudo chown postgres:postgres "$DEST"
sudo chmod 640 "$DEST"
sudo systemctl reload postgresql

echo "--- Vérification ---"
sudo -u postgres psql -c "SELECT pg_reload_conf();"
sudo grep -vE '^\s*#|^\s*$' "$DEST"
