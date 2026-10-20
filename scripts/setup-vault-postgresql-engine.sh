#!/usr/bin/env bash
# Crée le rôle PostgreSQL dédié à Vault (vault_admin) et configure le
# secrets engine "database" de Vault pour qu'il émette des identifiants
# PostgreSQL dynamiques, à durée de vie limitée, pour le rôle applicatif
# -- voir vault/README.md pour le détail des choix. Nécessite VAULT_ADDR
# et VAULT_TOKEN déjà exportés (droits suffisants pour activer un secrets
# engine).
#
# Mot de passe de vault_admin généré ici, utilisé immédiatement pour
# configurer Vault, jamais écrit sur disque -- une fois Vault configuré,
# Vault seul connaît ce mot de passe (stocké chiffré dans son storage).
set -euo pipefail

APP_ROLE="secure_web_lab_app"
APP_DB="secure_web_lab"
VAULT_PG_ROLE="vault_admin"

VAULT_PG_PASSWORD="$(openssl rand -hex 24)"

ROLE_EXISTS="$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${VAULT_PG_ROLE}'")"
if [[ "$ROLE_EXISTS" == "1" ]]; then
  echo "Rôle '${VAULT_PG_ROLE}' déjà présent -- mot de passe réinitialisé pour cette configuration."
  sudo -u postgres psql -c "ALTER ROLE ${VAULT_PG_ROLE} WITH PASSWORD '${VAULT_PG_PASSWORD}';"
else
  sudo -u postgres psql -c "CREATE ROLE ${VAULT_PG_ROLE} WITH LOGIN PASSWORD '${VAULT_PG_PASSWORD}' CREATEROLE;"
fi

# Permet à vault_admin d'accorder/révoquer l'appartenance à secure_web_lab_app
# sans lui donner SUPERUSER -- nécessaire pour que les rôles dynamiques
# créés "IN ROLE secure_web_lab_app" héritent de ses privilèges.
sudo -u postgres psql -c "GRANT ${APP_ROLE} TO ${VAULT_PG_ROLE} WITH ADMIN OPTION;"

echo "--- Secrets engine database ---"
if vault secrets list -format=json | grep -q '"database/"'; then
  echo "Secrets engine 'database' déjà activé -- poursuite."
else
  vault secrets enable database
fi

vault write database/config/secure-web-lab \
  plugin_name=postgresql-database-plugin \
  allowed_roles="secure-web-lab-app" \
  connection_url="postgresql://{{username}}:{{password}}@127.0.0.1:5432/${APP_DB}" \
  username="${VAULT_PG_ROLE}" \
  password="${VAULT_PG_PASSWORD}"

# IN ROLE : le rôle dynamique hérite des privilèges de secure_web_lab_app
# par simple appartenance -- aucun GRANT supplémentaire nécessaire par
# identifiant émis. VALID UNTIL '{{expiration}}' est une ceinture-et-
# bretelles côté PostgreSQL lui-même (expiration imposée par le SGBD, pas
# seulement par la révocation active de Vault à l'expiration du bail).
vault write database/roles/secure-web-lab-app \
  db_name=secure-web-lab \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}' IN ROLE ${APP_ROLE};" \
  revocation_statements="DROP ROLE IF EXISTS \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h"

unset VAULT_PG_PASSWORD

echo "--- Vérification : émission d'un identifiant dynamique réel ---"
vault read database/creds/secure-web-lab-app
