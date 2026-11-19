#!/usr/bin/env bash
# Installe Logstash depuis le même dépôt apt Elastic déjà configuré pour
# Elasticsearch/Kibana (scripts/install-elasticsearch.sh) -- aucune
# nouvelle clé GPG/source à ajouter.
set -euo pipefail

sudo apt-get update

CANDIDATE="$(apt-cache policy logstash | awk '/Candidate:/{print $2}')"
if [[ -z "$CANDIDATE" || "$CANDIDATE" == "(none)" ]]; then
  echo "Impossible de déterminer une version candidate pour 'logstash'." >&2
  exit 1
fi

sudo apt-get install -y "logstash=${CANDIDATE}"
sudo apt-mark hold logstash

echo "--- Vérification ---"
dpkg -s logstash | grep -E '^(Package|Version|Status)'
id logstash
