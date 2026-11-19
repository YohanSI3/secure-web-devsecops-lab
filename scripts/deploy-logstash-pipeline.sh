#!/usr/bin/env bash
# Déploie elk/logstash-pipeline.conf vers /etc/logstash/conf.d/ (déjà
# pointé par pipelines.yml du paquet, aucune autre modification
# nécessaire) et copie le certificat CA auto-généré d'Elasticsearch pour
# que Logstash (utilisateur dédié, pas elasticsearch) puisse vérifier le
# certificat TLS -- voir elk/README.md.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

sudo cp "${REPO_ROOT}/elk/logstash-pipeline.conf" /etc/logstash/conf.d/secure-web-lab.conf
sudo chown root:logstash /etc/logstash/conf.d/secure-web-lab.conf
sudo chmod 640 /etc/logstash/conf.d/secure-web-lab.conf

sudo mkdir -p /etc/logstash/certs
sudo cp /etc/elasticsearch/certs/http_ca.crt /etc/logstash/certs/http_ca.crt
sudo chown root:logstash /etc/logstash/certs/http_ca.crt
sudo chmod 640 /etc/logstash/certs/http_ca.crt

sudo systemctl enable logstash
sudo systemctl restart logstash

echo "--- Vérification ---"
sleep 15
sudo systemctl status logstash --no-pager -l
