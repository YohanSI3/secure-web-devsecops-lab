#!/usr/bin/env bash
# Configure ufw pour n'exposer que les ports réellement utilisés par ce lab.
# Voir firewall/README.md pour les règles retenues et pourquoi,
# Notes/ufw/ pour le fonctionnement général d'un firewall Linux.
set -euo pipefail

if ! command -v ufw >/dev/null; then
  sudo apt-get update
  sudo apt-get install -y ufw
fi

sudo ufw default deny incoming
sudo ufw default allow outgoing

sudo ufw allow 80/tcp   comment 'prod-lab HTTP (redirect vers HTTPS)'
sudo ufw allow 443/tcp  comment 'prod-lab HTTPS'
sudo ufw allow 8080/tcp comment 'dev HTTP (redirect vers HTTPS)'
sudo ufw allow 8443/tcp comment 'dev HTTPS'
sudo ufw allow 8081/tcp comment 'staging HTTP (redirect vers HTTPS)'
sudo ufw allow 8444/tcp comment 'staging HTTPS'

sudo ufw --force enable

echo "--- Vérification ---"
sudo ufw status verbose
