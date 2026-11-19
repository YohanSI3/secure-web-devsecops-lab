#!/usr/bin/env bash
# Déploie elk/filebeat.yml (versionné dans ce dépôt) vers
# /etc/filebeat/filebeat.yml -- remplacement complet sûr ici
# (contrairement à Elasticsearch/Kibana, voir elk/filebeat.yml pour
# pourquoi). Copié et chown root:root (Filebeat lit sa config en tant
# que root par défaut sur ce paquet), pas symlinké -- même logique que
# les autres services de ce lab.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

sudo cp "${REPO_ROOT}/elk/filebeat.yml" /etc/filebeat/filebeat.yml
sudo chown root:root /etc/filebeat/filebeat.yml
sudo chmod 600 /etc/filebeat/filebeat.yml

sudo systemctl enable filebeat
sudo systemctl restart filebeat

echo "--- Vérification ---"
sleep 3
sudo systemctl status filebeat --no-pager -l
