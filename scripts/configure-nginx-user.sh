#!/usr/bin/env bash
# Fait tourner les worker processes Nginx sous l'utilisateur dédié du lab
# (créé par scripts/create-nginx-user.sh) au lieu de www-data.
#
# Patch la directive `user` dans /etc/nginx/nginx.conf — fichier stock,
# volontairement non versionné dans ce dépôt (voir nginx/conf.d/security.conf
# et Notes/nginx/utilisateur-dedie/creation-et-configuration-utilisateur.md
# pour pourquoi cette directive précise ne peut pas passer par conf.d/snippets
# et doit être éditée en place) — puis ajuste les répertoires temporaires de
# Nginx, qui doivent appartenir au nouvel utilisateur.
set -euo pipefail

NGINX_USER="secure-web-lab"
NGINX_GROUP="secure-web-lab"
NGINX_CONF="/etc/nginx/nginx.conf"

if ! getent passwd "$NGINX_USER" >/dev/null; then
  echo "Utilisateur '${NGINX_USER}' introuvable — lancer d'abord scripts/create-nginx-user.sh" >&2
  exit 1
fi

if [[ ! -f "$NGINX_CONF" ]]; then
  echo "${NGINX_CONF} introuvable — Nginx est-il installé ?" >&2
  exit 1
fi

if grep -qE "^\s*user\s+${NGINX_USER}\s*;" "$NGINX_CONF"; then
  echo "'${NGINX_CONF}' déclare déjà 'user ${NGINX_USER};' — rien à faire."
else
  BACKUP="${NGINX_CONF}.bak-$(date +%Y%m%d%H%M%S)"
  sudo cp "$NGINX_CONF" "$BACKUP"
  sudo sed -i -E "s/^\s*user\s+.*;/user ${NGINX_USER};/" "$NGINX_CONF"
  echo "Directive 'user' mise à jour dans ${NGINX_CONF} (sauvegarde : ${BACKUP})."
fi

# Répertoires temporaires nginx (corps de requête, cache proxy/fastcgi/...) :
# ouverts en écriture par les workers eux-mêmes, contrairement aux logs (voir
# Notes/nginx/configuration/logs-et-privileges.md) -> doivent appartenir au
# nouvel utilisateur, sinon échec d'écriture sur les requêtes qui débordent
# en fichier temporaire (upload volumineux, réponse proxifiée, etc.).
if [[ -d /var/lib/nginx ]]; then
  sudo chown -R "${NGINX_USER}:${NGINX_GROUP}" /var/lib/nginx
  echo "Propriétaire de /var/lib/nginx mis à jour."
fi

sudo nginx -t
sudo systemctl reload nginx

echo "--- Vérification ---"
ps -eo user,pid,cmd | grep '[n]ginx: worker process'
