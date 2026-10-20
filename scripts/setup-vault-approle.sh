#!/usr/bin/env bash
# Active l'authentification AppRole et une policy en lecture seule,
# scopée aux deux seuls chemins dont le backend a réellement besoin --
# remplace l'usage du jeton racine au quotidien (jamais utilisé que pour
# la configuration initiale des secrets engines). Voir vault/README.md.
# Nécessite VAULT_ADDR et VAULT_TOKEN (droits suffisants) déjà exportés.
set -euo pipefail

POLICY_NAME="secure-web-lab-backend"
ROLE_NAME="secure-web-lab-backend"

echo "--- Policy : lecture seule, deux chemins précis uniquement ---"
vault policy write "${POLICY_NAME}" - <<'EOF'
# SESSION_SECRET (KV v2 -- voir scripts/setup-vault-kv.sh)
path "secret/data/secure-web-lab/backend" {
  capabilities = ["read"]
}

# Identifiants PostgreSQL dynamiques (voir scripts/setup-vault-postgresql-engine.sh)
path "database/creds/secure-web-lab-app" {
  capabilities = ["read"]
}
EOF

echo "--- Méthode d'authentification AppRole ---"
if vault auth list -format=json | grep -q '"approle/"'; then
  echo "AppRole déjà activée -- poursuite."
else
  vault auth enable approle
fi

# token_ttl/token_max_ttl courts : le jeton obtenu après connexion expire
# vite et doit être renouvelé -- le couple role_id/secret_id, lui, agit
# comme une identité de longue durée pour cette seule machine (comparable
# à une clé SSH de service), jamais comme un accès permanent à Vault.
vault write auth/approle/role/"${ROLE_NAME}" \
  token_policies="${POLICY_NAME}" \
  token_ttl=15m \
  token_max_ttl=1h \
  secret_id_ttl=0 \
  secret_id_num_uses=0

echo "--- role_id (identifiant, pas un secret -- comparable à un nom d'utilisateur) ---"
vault read auth/approle/role/"${ROLE_NAME}"/role-id

echo "--- Génération d'un secret_id (sensible -- jamais à committer, voir vault/README.md) ---"
vault write -f auth/approle/role/"${ROLE_NAME}"/secret-id
