#!/usr/bin/env bash
# Installe Filebeat depuis le même dépôt apt Elastic déjà configuré pour
# Elasticsearch/Kibana (scripts/install-elasticsearch.sh) -- aucune
# nouvelle clé GPG/source à ajouter.
set -euo pipefail

sudo apt-get update

CANDIDATE="$(apt-cache policy filebeat | awk '/Candidate:/{print $2}')"
if [[ -z "$CANDIDATE" || "$CANDIDATE" == "(none)" ]]; then
  echo "Impossible de déterminer une version candidate pour 'filebeat'." >&2
  exit 1
fi

sudo apt-get install -y "filebeat=${CANDIDATE}"
sudo apt-mark hold filebeat

echo "--- Vérification ---"
dpkg -s filebeat | grep -E '^(Package|Version|Status)'
