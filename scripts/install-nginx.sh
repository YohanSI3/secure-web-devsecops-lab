#!/usr/bin/env bash
# Installe Nginx dans une version pinnée pour garantir un environnement
# reproductible entre machines/contributeurs. Voir Notes/nginx/installation/.
set -euo pipefail

NGINX_VERSION="1.24.0-2ubuntu7.17"
EXPECTED_CODENAME="noble"

codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-unknown}")"
if [[ "$codename" != "$EXPECTED_CODENAME" ]]; then
  echo "ATTENTION: ce script cible Ubuntu ${EXPECTED_CODENAME} (24.04)." >&2
  echo "OS détecté: ${codename}. La version pinnée (${NGINX_VERSION}) risque" >&2
  echo "de ne pas être disponible dans vos dépôts apt. Poursuite quand même..." >&2
fi

sudo apt-get update
sudo apt-get install -y "nginx=${NGINX_VERSION}" "nginx-common=${NGINX_VERSION}"

# Empêche apt upgrade/dist-upgrade de faire dériver la version silencieusement.
sudo apt-mark hold nginx nginx-common

echo "--- Vérification ---"
nginx -v
systemctl is-active nginx || true
systemctl is-enabled nginx || true
