#!/usr/bin/env bash
# Déploie le contenu et la config nginx pour les trois environnements du
# lab (dev, staging, prod). Voir Notes/nginx/environnements/.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for env in dev staging prod; do
  echo "=== ${env} ==="
  "${REPO_ROOT}/scripts/deploy-static-site.sh" "$env"
  "${REPO_ROOT}/scripts/deploy-nginx-config.sh" "$env"
done
