#!/usr/bin/env bash
# Enrôle Kibana auprès d'Elasticsearch : jeton d'enrôlement généré puis
# consommé dans la même commande, jamais affiché ni manipulé
# manuellement -- contrairement au mot de passe elastic (affiché une
# fois à l'écran, voir elk/README.md), ce jeton n'a aucune raison d'être
# vu par l'opérateur. À lancer une seule fois, avant le premier démarrage
# du service Kibana (scripts/deploy-kibana-config.sh).
set -euo pipefail

TOKEN="$(sudo /usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token -s kibana)"

sudo /usr/share/kibana/bin/kibana-setup --enrollment-token="$TOKEN"
