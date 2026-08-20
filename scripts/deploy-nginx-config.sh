#!/usr/bin/env bash
# Active la config nginx versionnée du repo dans /etc/nginx via symlink,
# désactive le site "default", vérifie la syntaxe, recharge nginx.
# Voir Notes/nginx/configuration/repo-vs-etc-nginx.md.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF_NAME="secure-web-lab.conf"
CONF_SRC="${REPO_ROOT}/nginx/sites-available/${CONF_NAME}"

sudo ln -sf "$CONF_SRC" "/etc/nginx/sites-available/${CONF_NAME}"
sudo ln -sf "/etc/nginx/sites-available/${CONF_NAME}" "/etc/nginx/sites-enabled/${CONF_NAME}"

if [[ -e /etc/nginx/sites-enabled/default ]]; then
  sudo rm /etc/nginx/sites-enabled/default
fi

sudo nginx -t
sudo systemctl reload nginx

echo "--- Sites actifs ---"
ls -la /etc/nginx/sites-enabled/
