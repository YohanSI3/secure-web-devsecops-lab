#!/usr/bin/env bash
# Crée l'utilisateur et le groupe système dédiés aux worker processes Nginx
# de ce lab, à la place du www-data partagé par défaut avec d'autres
# services éventuels de la machine. Idempotent : ne recrée rien si déjà
# présent. Voir Notes/nginx/utilisateur-dedie/.
set -euo pipefail

NGINX_USER="secure-web-lab"
NGINX_GROUP="secure-web-lab"

if getent group "$NGINX_GROUP" >/dev/null; then
  echo "Groupe '${NGINX_GROUP}' déjà présent — rien à faire."
else
  sudo groupadd --system "$NGINX_GROUP"
  echo "Groupe '${NGINX_GROUP}' créé."
fi

if getent passwd "$NGINX_USER" >/dev/null; then
  echo "Utilisateur '${NGINX_USER}' déjà présent — rien à faire."
else
  sudo useradd --system \
    --no-create-home \
    --shell /usr/sbin/nologin \
    --gid "$NGINX_GROUP" \
    --comment "Worker processes Nginx (secure-web-devsecops-lab)" \
    "$NGINX_USER"
  echo "Utilisateur '${NGINX_USER}' créé."
fi

echo "--- Vérification ---"
getent passwd "$NGINX_USER"
getent group "$NGINX_GROUP"
id "$NGINX_USER"
