#!/usr/bin/env bash
# Prépare et déploie le TLS local pour les trois environnements : CA (si
# absente), certificats serveur, déploiement dans /etc/nginx/ssl/.
# Étape séparée de deploy-all-environments.sh : la génération/déploiement
# de matériel cryptographique est un geste délibéré, pas une action à
# répéter silencieusement à chaque déploiement de contenu.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${REPO_ROOT}/scripts/generate-local-ca.sh"

for env in dev staging prod; do
  echo "=== ${env} ==="
  "${REPO_ROOT}/scripts/generate-server-cert.sh" "$env"
  "${REPO_ROOT}/scripts/deploy-tls-cert.sh" "$env"
done
