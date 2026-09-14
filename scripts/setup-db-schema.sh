#!/usr/bin/env bash
# Applique app/backend/db/schema.sql à la base applicative, via le rôle
# dédié lui-même (pas postgres/superuser) -- lit DATABASE_URL depuis
# app/backend/.env, généré par scripts/setup-postgres-db.sh. Idempotent :
# le schéma n'utilise que CREATE TABLE IF NOT EXISTS.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/app/backend/.env"
SCHEMA_FILE="${REPO_ROOT}/app/backend/db/schema.sql"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "${ENV_FILE} introuvable — lancer d'abord scripts/setup-postgres-db.sh" >&2
  exit 1
fi

DATABASE_URL="$(grep '^DATABASE_URL=' "$ENV_FILE" | cut -d= -f2-)"
if [[ -z "$DATABASE_URL" ]]; then
  echo "DATABASE_URL absent de ${ENV_FILE}" >&2
  exit 1
fi

psql "$DATABASE_URL" -f "$SCHEMA_FILE"

echo "--- Vérification ---"
psql "$DATABASE_URL" -c "\dt"
