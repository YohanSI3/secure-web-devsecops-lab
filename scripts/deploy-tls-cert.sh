#!/usr/bin/env bash
# Déploie le certificat/clé déjà générés (.tls/<env>/) vers
# /etc/nginx/ssl/<env>/. Ne génère rien lui-même.
# Voir Notes/nginx/tls/deploiement-et-permissions.md.
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
SRC_DIR="${REPO_ROOT}/.tls/${ENV}"
DEST_DIR="/etc/nginx/ssl/${ENV}"

if [[ ! -f "${SRC_DIR}/server.crt" || ! -f "${SRC_DIR}/server.key" ]]; then
  echo "Certificat introuvable pour '${ENV}' — lancer d'abord:" >&2
  echo "  scripts/generate-server-cert.sh ${ENV}" >&2
  exit 1
fi

sudo mkdir -p "$DEST_DIR"
sudo cp "${SRC_DIR}/server.crt" "${DEST_DIR}/server.crt"
sudo cp "${SRC_DIR}/server.key" "${DEST_DIR}/server.key"

# Clé privée : lue une seule fois par le master process (root) au
# chargement, jamais par les workers -> pas besoin du groupe www-data ici,
# contrairement au webroot (voir Notes/nginx/configuration/permissions-webroot.md).
sudo chown root:root "${DEST_DIR}/server.crt" "${DEST_DIR}/server.key"
sudo chmod 644 "${DEST_DIR}/server.crt"
sudo chmod 600 "${DEST_DIR}/server.key"

echo "--- Déployé dans ${DEST_DIR} ---"
sudo ls -la "$DEST_DIR"
