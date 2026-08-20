#!/usr/bin/env bash
# Déploie app/static-site/ (source versionnée) vers /var/www/secure-web-lab/
# (webroot servi par nginx). Voir Notes/nginx/configuration/permissions-webroot.md.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${REPO_ROOT}/app/static-site/"
DEST="/var/www/secure-web-lab"

sudo mkdir -p "$DEST"
sudo rsync -a --delete "$SRC" "$DEST/"

# Modèle de moindre privilège : root possède les fichiers, le groupe
# www-data (groupe du worker nginx) peut lire/traverser, aucun accès "other".
sudo chown -R root:www-data "$DEST"
sudo find "$DEST" -type d -exec chmod 750 {} \;
sudo find "$DEST" -type f -exec chmod 640 {} \;

echo "--- Déployé dans ${DEST} ---"
ls -la "$DEST"
