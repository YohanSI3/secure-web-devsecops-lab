#!/usr/bin/env bash
# Étend (jamais ne remplace) /etc/elasticsearch/elasticsearch.yml généré
# par le paquet -- voir elk/README.md pour le bug réel rencontré en
# remplaçant tout le fichier avec une version minimale (perte de
# path.data/path.logs, puis des réglages TLS/mots de passe de
# l'auto-configuration de sécurité).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST=/etc/elasticsearch/elasticsearch.yml
MARKER="# --- secure-web-devsecops-lab : réglages ajoutés ---"

if sudo grep -qF "$MARKER" "$DEST" 2>/dev/null; then
  echo "Réglages déjà appliqués (marqueur trouvé) -- rien à refaire sur elasticsearch.yml."
else
  # Retire les deux lignes du bloc d'auto-configuration de sécurité que
  # nos propres réglages remplacent (http.host, cluster.initial_master_nodes)
  # -- sinon deux clés YAML identiques dans le même fichier provoqueraient
  # une erreur de parsing au démarrage. Les certificats/mots de passe
  # générés par l'auto-configuration, eux, ne sont jamais touchés.
  sudo sed -i -E '/^http\.host:/d; /^cluster\.initial_master_nodes:/d' "$DEST"

  {
    echo ""
    echo "$MARKER"
    cat "${REPO_ROOT}/elk/elasticsearch-overrides.yml"
  } | sudo tee -a "$DEST" > /dev/null
fi

sudo mkdir -p /etc/elasticsearch/jvm.options.d
sudo cp "${REPO_ROOT}/elk/jvm-heap.options" /etc/elasticsearch/jvm.options.d/heap.options
sudo chown root:elasticsearch /etc/elasticsearch/jvm.options.d/heap.options
sudo chmod 660 /etc/elasticsearch/jvm.options.d/heap.options

sudo systemctl daemon-reload
sudo systemctl enable elasticsearch
sudo systemctl restart elasticsearch

echo "--- Vérification ---"
sleep 10
sudo systemctl status elasticsearch --no-pager -l
