#!/usr/bin/env bash
# Génère une CA locale auto-signée pour le lab, dans .tls/ca/ (jamais
# commité — voir .gitignore). Idempotent : ne régénère pas une CA déjà
# présente, pour ne pas invalider les certificats déjà émis avec elle.
# Voir Notes/nginx/tls/local-ca-et-chaine-de-confiance.md.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CA_DIR="${REPO_ROOT}/.tls/ca"

if [[ -f "${CA_DIR}/ca.key" ]]; then
  echo "CA locale déjà présente dans ${CA_DIR} — rien à faire."
  echo "(pour en régénérer une nouvelle, supprimer ${CA_DIR} d'abord)"
  exit 0
fi

mkdir -p "$CA_DIR"

openssl genrsa -out "${CA_DIR}/ca.key" 4096
chmod 600 "${CA_DIR}/ca.key"

openssl req -x509 -new -nodes \
  -key "${CA_DIR}/ca.key" \
  -sha256 -days 3650 \
  -subj "/O=secure-web-devsecops-lab/CN=secure-web-lab local CA" \
  -out "${CA_DIR}/ca.crt"

echo "--- CA générée dans ${CA_DIR} ---"
openssl x509 -in "${CA_DIR}/ca.crt" -noout -subject -dates
