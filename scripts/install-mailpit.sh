#!/usr/bin/env bash
# Installe Mailpit (capteur SMTP local) : simule l'envoi des emails de
# réinitialisation de mot de passe sans dépendre d'un vrai fournisseur ni
# jamais envoyer de vrai email -- voir app/backend/README.md et
# Notes/iam/reinitialisation-mot-de-passe.md. Version pinnée (téléchargée
# depuis une release GitHub taguée précisément, pas "latest"), même
# logique que les autres scripts d'install de ce dépôt. Aucun fichier de
# checksums n'est publié par le projet Mailpit pour cette release --
# limite connue, pas de vérification cryptographique possible au-delà de
# HTTPS + confiance dans le dépôt GitHub officiel.
set -euo pipefail

MAILPIT_VERSION="1.31.1"
INSTALL_PATH="/usr/local/bin/mailpit"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

curl -fsSL \
  "https://github.com/axllent/mailpit/releases/download/v${MAILPIT_VERSION}/mailpit-linux-amd64.tar.gz" \
  -o "${TMP_DIR}/mailpit.tar.gz"
tar -xzf "${TMP_DIR}/mailpit.tar.gz" -C "$TMP_DIR" mailpit
sudo install -o root -g root -m 755 "${TMP_DIR}/mailpit" "$INSTALL_PATH"

# Utilisateur système dédié, même philosophie que les workers Nginx (voir
# Notes/nginx/utilisateur-dedie/) : un compte de service par service,
# jamais root, jamais partagé.
if ! getent passwd mailpit >/dev/null; then
  sudo useradd --system --no-create-home --shell /usr/sbin/nologin mailpit
  echo "Utilisateur système 'mailpit' créé."
fi

sudo tee /etc/systemd/system/mailpit.service > /dev/null <<'EOF'
[Unit]
Description=Mailpit (capteur SMTP local, usage lab uniquement)
After=network.target

[Service]
User=mailpit
Group=mailpit
ExecStart=/usr/local/bin/mailpit --listen 127.0.0.1:8025 --smtp 127.0.0.1:1025
Restart=on-failure

# Sandboxing systemd : Mailpit analyse des flux SMTP non fiables (n'importe
# quel process local peut lui envoyer un email) -- ces restrictions limitent
# ce qu'un Mailpit compromis pourrait faire même en cas de faille dans le
# binaire lui-même.
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now mailpit

echo "--- Vérification ---"
sleep 1
sudo systemctl is-active mailpit
curl -sf http://127.0.0.1:8025/api/v1/info
