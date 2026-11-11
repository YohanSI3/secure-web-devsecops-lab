#!/usr/bin/env bash
# Active la config nginx versionnée de l'environnement demandé dans
# /etc/nginx via symlink (site + conf.d + snippets globaux), désactive le
# site "default", vérifie la syntaxe, recharge nginx.
# Voir Notes/nginx/configuration/repo-vs-etc-nginx.md,
# Notes/nginx/environnements/ et Notes/nginx/headers-securite/.
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
CONF_NAME="secure-web-lab-${ENV}.conf"
CONF_SRC="${REPO_ROOT}/nginx/sites-available/${CONF_NAME}"

# Config globale (conf.d/) et fragments réutilisables (snippets/) : mêmes
# fichiers pour les trois environnements, reliés à chaque exécution.
sudo mkdir -p /etc/nginx/snippets
for f in "${REPO_ROOT}"/nginx/conf.d/*.conf; do
  sudo ln -sf "$f" "/etc/nginx/conf.d/$(basename "$f")"
done
for f in "${REPO_ROOT}"/nginx/snippets/*.conf; do
  sudo ln -sf "$f" "/etc/nginx/snippets/$(basename "$f")"
done

sudo ln -sf "$CONF_SRC" "/etc/nginx/sites-available/${CONF_NAME}"
sudo ln -sf "/etc/nginx/sites-available/${CONF_NAME}" "/etc/nginx/sites-enabled/${CONF_NAME}"

if [[ -e /etc/nginx/sites-enabled/default ]]; then
  sudo rm /etc/nginx/sites-enabled/default
fi

# Versions récentes du paquet nginx Ubuntu ajoutent elles-mêmes
# "server_tokens build;" au niveau http du nginx.conf stock (non
# versionné) -- entre en conflit (erreur "duplicate", pas une fusion
# comme ssl_protocols) avec notre propre déclaration, plus stricte (off,
# dans nginx/conf.d/security.conf). Une seule déclaration peut survivre :
# la nôtre. Découvert en CI (apt installe toujours la version courante)
# avant de toucher cette machine (nginx figé par apt-mark hold depuis la
# Phase 1) -- voir nginx/README.md#protection-contre-divulgation-de-version.
sudo sed -i '/^\s*server_tokens\b/d' /etc/nginx/nginx.conf

sudo nginx -t
sudo systemctl reload nginx

echo "--- Sites actifs ---"
ls -la /etc/nginx/sites-enabled/
