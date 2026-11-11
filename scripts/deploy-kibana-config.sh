#!/usr/bin/env bash
# Étend /etc/kibana/kibana.yml avec elk/kibana-overrides.yml (append, pas
# de remplacement -- voir elk/kibana-overrides.yml pour pourquoi un
# simple ajout suffit ici, contrairement à Elasticsearch). Idempotent via
# un marqueur en commentaire. Ne gère PAS l'enrôlement auprès
# d'Elasticsearch -- voir scripts/enroll-kibana.sh, à lancer séparément
# avant le premier démarrage.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST=/etc/kibana/kibana.yml
MARKER="# --- secure-web-devsecops-lab : réglages ajoutés ---"

if sudo grep -qF "$MARKER" "$DEST" 2>/dev/null; then
  echo "Réglages déjà appliqués (marqueur trouvé) -- rien à refaire sur kibana.yml."
else
  {
    echo ""
    echo "$MARKER"
    cat "${REPO_ROOT}/elk/kibana-overrides.yml"
  } | sudo tee -a "$DEST" > /dev/null
fi

sudo systemctl daemon-reload
sudo systemctl enable kibana
sudo systemctl restart kibana

echo "--- Vérification ---"
sleep 10
sudo systemctl status kibana --no-pager -l
