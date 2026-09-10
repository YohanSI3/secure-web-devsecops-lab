#!/usr/bin/env bash
# Enchaîne la création de l'utilisateur système dédié et la reconfiguration
# de Nginx pour l'utiliser. Étape séparée de deploy-all-environments.sh au
# même titre que setup-tls.sh : un changement d'identité système est un
# geste délibéré, pas une action à répéter silencieusement à chaque
# déploiement de contenu. Voir Notes/nginx/utilisateur-dedie/.
#
# À exécuter une fois, puis redéployer le contenu (deploy-all-environments.sh
# ou deploy-static-site.sh) pour que la propriété du webroot suive le
# nouveau groupe.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${REPO_ROOT}/scripts/create-nginx-user.sh"
"${REPO_ROOT}/scripts/configure-nginx-user.sh"
