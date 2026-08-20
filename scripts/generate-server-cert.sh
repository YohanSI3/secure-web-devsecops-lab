#!/usr/bin/env bash
# Génère une clé privée + certificat serveur pour un environnement, signés
# par la CA locale (.tls/ca/). Écrase le certificat existant à chaque
# exécution (contrairement à la CA, un certificat serveur n'a pas de
# dépendant à invalider en le régénérant).
# Voir Notes/nginx/tls/certificats-serveur-et-san.md.
set -euo pipefail

ENV="${1:-}"
case "$ENV" in
  dev)     DOMAIN="dev.secure-web-lab.local" ;;
  staging) DOMAIN="staging.secure-web-lab.local" ;;
  prod)    DOMAIN="secure-web-lab.local" ;;
  *)
    echo "Usage: $0 <dev|staging|prod>" >&2
    exit 1
    ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CA_DIR="${REPO_ROOT}/.tls/ca"
ENV_DIR="${REPO_ROOT}/.tls/${ENV}"

if [[ ! -f "${CA_DIR}/ca.key" ]]; then
  echo "CA locale introuvable — lancer d'abord scripts/generate-local-ca.sh" >&2
  exit 1
fi

mkdir -p "$ENV_DIR"

openssl genrsa -out "${ENV_DIR}/server.key" 2048
chmod 600 "${ENV_DIR}/server.key"

openssl req -new \
  -key "${ENV_DIR}/server.key" \
  -subj "/CN=${DOMAIN}" \
  -out "${ENV_DIR}/server.csr"

cat > "${ENV_DIR}/server.ext" <<EOF
subjectAltName = DNS:${DOMAIN}
EOF

openssl x509 -req \
  -in "${ENV_DIR}/server.csr" \
  -CA "${CA_DIR}/ca.crt" -CAkey "${CA_DIR}/ca.key" -CAcreateserial \
  -out "${ENV_DIR}/server.crt" \
  -days 397 -sha256 \
  -extfile "${ENV_DIR}/server.ext"

echo "--- Certificat généré pour ${DOMAIN} (${ENV}) ---"
openssl x509 -in "${ENV_DIR}/server.crt" -noout -subject -ext subjectAltName -dates
