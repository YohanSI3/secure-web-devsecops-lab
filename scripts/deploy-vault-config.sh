#!/usr/bin/env bash
# Déploie vault/config.hcl (versionné dans ce dépôt) vers
# /etc/vault.d/vault.hcl -- copié et chown vault:vault (pas symlinké),
# même logique que scripts/deploy-postgresql-hba.sh : Vault lit sa config
# au démarrage du service, qui tourne sous l'utilisateur dédié `vault`
# (créé par le paquet, voir scripts/install-vault.sh) -- un fichier
# possédé par l'utilisateur courant, même seulement lisible, s'écarte du
# modèle de permissions attendu par le paquet.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${REPO_ROOT}/vault/config.hcl"
DEST="/etc/vault.d/vault.hcl"

sudo mkdir -p /opt/vault/data
sudo chown -R vault:vault /opt/vault

sudo cp "$SRC" "$DEST"
sudo chown vault:vault "$DEST"
sudo chmod 640 "$DEST"

sudo systemctl enable vault
sudo systemctl restart vault

echo "--- Vérification ---"
sleep 2
sudo systemctl status vault --no-pager -l
export VAULT_ADDR="http://127.0.0.1:8200"
vault status || true
