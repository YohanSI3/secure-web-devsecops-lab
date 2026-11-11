#!/usr/bin/env bash
# Installe Kibana depuis le même dépôt apt Elastic déjà configuré pour
# Elasticsearch (scripts/install-elasticsearch.sh) -- pas de nouvelle clé
# GPG/source à ajouter, Kibana est publié dans le même dépôt ligne 9.x.
set -euo pipefail

sudo apt-get update

CANDIDATE="$(apt-cache policy kibana | awk '/Candidate:/{print $2}')"
if [[ -z "$CANDIDATE" || "$CANDIDATE" == "(none)" ]]; then
  echo "Impossible de déterminer une version candidate pour 'kibana'." >&2
  exit 1
fi

sudo apt-get install -y "kibana=${CANDIDATE}"
sudo apt-mark hold kibana

echo "--- Vérification ---"
dpkg -s kibana | grep -E '^(Package|Version|Status)'
id kibana
