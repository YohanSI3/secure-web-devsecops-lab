#!/usr/bin/env bash
# Installe PostgreSQL depuis les dépôts officiels Ubuntu (contrairement à
# Node.js, PostgreSQL y est disponible à une version raisonnablement
# récente et maintenue -- pas besoin d'un dépôt tiers ici). Version
# résolue dynamiquement puis épinglée, même logique que
# scripts/install-nginx.sh mais sans version codée en dur (impossible à
# vérifier par avance sans accès à la machine cible au moment de l'écriture).
set -euo pipefail

sudo apt-get update

CANDIDATE="$(apt-cache policy postgresql | awk '/Candidate:/{print $2}')"
if [[ -z "$CANDIDATE" || "$CANDIDATE" == "(none)" ]]; then
  echo "Impossible de déterminer une version candidate pour 'postgresql'." >&2
  exit 1
fi

sudo apt-get install -y "postgresql=${CANDIDATE}" "postgresql-contrib=${CANDIDATE}"
sudo apt-mark hold postgresql postgresql-contrib

echo "--- Vérification ---"
sudo systemctl is-active postgresql
sudo -u postgres psql -c "SELECT version();"
