#!/usr/bin/env bash
# Active le secrets engine KV v2 et y migre SESSION_SECRET depuis
# app/backend/.env -- voir vault/README.md. Nécessite VAULT_ADDR et
# VAULT_TOKEN déjà exportés dans le shell courant (jeton avec droits
# suffisants ; le jeton racine convient pour cette mise en place initiale,
# voir vault/README.md pour l'AppRole prévu ensuite pour l'usage courant
# du backend).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/app/backend/.env"

SESSION_SECRET="$(grep '^SESSION_SECRET=' "$ENV_FILE" | cut -d= -f2-)"
if [[ -z "$SESSION_SECRET" ]]; then
  echo "SESSION_SECRET introuvable dans ${ENV_FILE}." >&2
  exit 1
fi

if vault secrets list -format=json | grep -q '"secret/"'; then
  echo "Secrets engine KV v2 déjà activé sur 'secret/' -- poursuite."
else
  vault secrets enable -path=secret kv-v2
fi

vault kv put secret/secure-web-lab/backend SESSION_SECRET="$SESSION_SECRET"

echo "--- Vérification (clés présentes, pas les valeurs) ---"
vault kv get -format=json secret/secure-web-lab/backend | grep -o '"[A-Z_]*":' | sort -u
