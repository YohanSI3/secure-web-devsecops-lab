#!/usr/bin/env bash
# Génère les clés de chiffrement internes de Kibana (sessions, objets
# sauvegardés chiffrés, reporting) et les ajoute directement à
# kibana.yml -- jamais affichées, même logique que le jeton d'enrôlement
# (scripts/enroll-kibana.sh). Sans ces clés, Kibana en génère une
# aléatoire à chaque démarrage (sessions invalidées à chaque redémarrage)
# et désactive purement et simplement les API Alerting/Actions -- un
# problème réel pour ce lab, qui a besoin des alertes Kibana plus loin
# dans la Phase 6.
set -euo pipefail

DEST=/etc/kibana/kibana.yml
MARKER="# --- secure-web-devsecops-lab : clés de chiffrement générées ---"

if sudo grep -qF "$MARKER" "$DEST" 2>/dev/null; then
  echo "Clés déjà générées (marqueur trouvé) -- rien à refaire."
  exit 0
fi

KEYS="$(sudo /usr/share/kibana/bin/kibana-encryption-keys generate -q)"

{
  echo ""
  echo "$MARKER"
  echo "$KEYS"
} | sudo tee -a "$DEST" > /dev/null

sudo systemctl restart kibana
echo "Clés ajoutées à ${DEST} et service redémarré."
