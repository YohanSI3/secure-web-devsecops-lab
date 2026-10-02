#!/usr/bin/env bash
# Durcissement PostgreSQL : privilèges base minimaux, timeouts par rôle,
# journalisation des connexions -- complète scripts/setup-postgres-db.sh
# (création du rôle/de la base) sans le refaire. Idempotent : chaque
# commande peut être rejouée sans effet de bord différent.
# Voir postgresql/README.md pour le détail de chaque choix.
set -euo pipefail

APP_ROLE="secure_web_lab_app"
APP_DB="secure_web_lab"

echo "--- Privilèges base : retire l'accès par défaut à PUBLIC ---"
sudo -u postgres psql -c "REVOKE CONNECT ON DATABASE ${APP_DB} FROM PUBLIC;"
sudo -u postgres psql -c "GRANT CONNECT ON DATABASE ${APP_DB} TO ${APP_ROLE};"

echo "--- Timeouts par rôle applicatif ---"
sudo -u postgres psql -c "ALTER ROLE ${APP_ROLE} SET statement_timeout = '15s';"
sudo -u postgres psql -c "ALTER ROLE ${APP_ROLE} SET idle_in_transaction_session_timeout = '30s';"

echo "--- Journalisation : connexions, déconnexions, hôte distant ---"
sudo -u postgres psql -c "ALTER SYSTEM SET log_connections = 'on';"
sudo -u postgres psql -c "ALTER SYSTEM SET log_disconnections = 'on';"
sudo -u postgres psql -c "ALTER SYSTEM SET log_line_prefix = '%m [%p] %q%u@%d %h ';"
sudo -u postgres psql -c "SELECT pg_reload_conf();"

echo "--- Vérification ---"
sudo -u postgres psql -c "\l+ ${APP_DB}"
sudo -u postgres psql -c "SELECT rolname, rolconfig FROM pg_roles WHERE rolname = '${APP_ROLE}';"
sudo -u postgres psql -c "SHOW log_connections;"
sudo -u postgres psql -c "SHOW log_disconnections;"
sudo -u postgres psql -c "SHOW log_line_prefix;"
