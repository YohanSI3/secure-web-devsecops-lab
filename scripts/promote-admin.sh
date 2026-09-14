#!/usr/bin/env bash
# Promeut un compte existant au rôle "admin". Aucune route API ne permet
# de le faire soi-même (un utilisateur ne peut jamais s'auto-promouvoir) --
# geste volontairement réservé à un accès direct à la base, comme la
# création du tout premier compte admin d'une vraie application.
set -euo pipefail

EMAIL="${1:-}"
if [[ -z "$EMAIL" ]]; then
  echo "Usage: $0 <email>" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/app/backend/.env"
DATABASE_URL="$(grep '^DATABASE_URL=' "$ENV_FILE" | cut -d= -f2-)"

psql "$DATABASE_URL" -c "UPDATE users SET role = 'admin' WHERE email = '${EMAIL}';"
psql "$DATABASE_URL" -c "SELECT id, email, role FROM users WHERE email = '${EMAIL}';"
