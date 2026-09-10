#!/usr/bin/env bash
# Déploie app/static-site/ (source versionnée) vers le webroot de
# l'environnement demandé (/var/www/secure-web-lab-<env>).
# Voir Notes/nginx/configuration/permissions-webroot.md,
# Notes/nginx/environnements/ et Notes/nginx/utilisateur-dedie/
# (groupe propriétaire = groupe du worker nginx, pas www-data).
set -euo pipefail

ENV="${1:-}"
case "$ENV" in
  dev|staging|prod) ;;
  *)
    echo "Usage: $0 <dev|staging|prod>" >&2
    exit 1
    ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${REPO_ROOT}/app/static-site/"
DEST="/var/www/secure-web-lab-${ENV}"
WEB_GROUP="secure-web-lab"

sudo mkdir -p "$DEST"
sudo rsync -a --delete "$SRC" "$DEST/"

# Modèle de moindre privilège : root possède les fichiers, le groupe du
# worker nginx peut lire/traverser, aucun accès "other".
sudo chown -R "root:${WEB_GROUP}" "$DEST"
sudo find "$DEST" -type d -exec chmod 750 {} \;
sudo find "$DEST" -type f -exec chmod 640 {} \;

echo "--- Déployé (${ENV}) dans ${DEST} ---"
ls -la "$DEST"
