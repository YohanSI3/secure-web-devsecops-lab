#!/usr/bin/env bash
# Crée le rôle et la base PostgreSQL dédiés à l'application, avec des
# privilèges minimaux -- même philosophie que l'utilisateur système dédié
# des workers Nginx (voir Notes/nginx/utilisateur-dedie/) : un rôle par
# application, propriétaire de sa propre base, sans droit CREATEDB,
# CREATEROLE ni SUPERUSER (aucun de ces droits n'est accordé par un
# simple CREATE ROLE ... LOGIN), et sans accès à une autre base que la
# sienne. Écrit le mot de passe généré dans app/backend/.env (jamais
# commité, voir app/backend/.gitignore) -- jamais en argument de ligne de
# commande affiché dans l'historique shell au-delà de ce script lui-même.
set -euo pipefail

APP_ROLE="secure_web_lab_app"
APP_DB="secure_web_lab"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/app/backend/.env"

ROLE_EXISTS="$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${APP_ROLE}'")"

if [[ "$ROLE_EXISTS" == "1" ]]; then
  echo "Rôle '${APP_ROLE}' déjà présent — mot de passe non régénéré."
  if [[ ! -f "$ENV_FILE" ]] || ! grep -q '^DATABASE_URL=' "$ENV_FILE"; then
    echo "ATTENTION: rôle existant mais DATABASE_URL absent de ${ENV_FILE}." >&2
    echo "Le mot de passe existant n'est pas récupérable en clair depuis PostgreSQL." >&2
    echo "Soit le retrouver depuis une sauvegarde de .env, soit :" >&2
    echo "  sudo -u postgres psql -c \"DROP DATABASE ${APP_DB};\"" >&2
    echo "  sudo -u postgres psql -c \"DROP ROLE ${APP_ROLE};\"" >&2
    echo "puis relancer ce script pour régénérer un mot de passe propre." >&2
    exit 1
  fi
else
  APP_PASSWORD="$(openssl rand -base64 24)"
  sudo -u postgres psql -c "CREATE ROLE ${APP_ROLE} LOGIN PASSWORD '${APP_PASSWORD}';"
  sudo -u postgres psql -c "CREATE DATABASE ${APP_DB} OWNER ${APP_ROLE};"

  mkdir -p "$(dirname "$ENV_FILE")"
  touch "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  echo "DATABASE_URL=postgresql://${APP_ROLE}:${APP_PASSWORD}@127.0.0.1:5432/${APP_DB}" >> "$ENV_FILE"
  echo "Rôle '${APP_ROLE}' et base '${APP_DB}' créés, DATABASE_URL ajouté à ${ENV_FILE}."
fi

echo "--- Vérification ---"
sudo -u postgres psql -c "\du ${APP_ROLE}"
sudo -u postgres psql -c "\l ${APP_DB}"
