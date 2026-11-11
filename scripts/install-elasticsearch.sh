#!/usr/bin/env bash
# Installe Elasticsearch depuis le dépôt apt officiel Elastic (ligne 9.x,
# vérifiée comme la ligne actuellement maintenue au moment de l'écriture
# -- voir elk/README.md). Même exception déjà documentée pour
# NodeSource/HashiCorp : pas dans les dépôts Ubuntu, canal officiellement
# recommandé par l'éditeur.
set -euo pipefail

KEYRING=/usr/share/keyrings/elasticsearch-keyring.gpg

sudo apt-get update
sudo apt-get install -y apt-transport-https gnupg

# Téléchargement et import de la clé séparés (pas un `curl | gpg` direct)
# -- même raisonnement que scripts/install-nodejs.sh/install-vault.sh.
KEY_FILE="$(mktemp)"
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch -o "$KEY_FILE"
sudo gpg --batch --yes --dearmor -o "$KEYRING" "$KEY_FILE"
rm -f "$KEY_FILE"

echo "deb [signed-by=${KEYRING}] https://artifacts.elastic.co/packages/9.x/apt stable main" \
  | sudo tee /etc/apt/sources.list.d/elastic-9.x.list > /dev/null

sudo apt-get update

CANDIDATE="$(apt-cache policy elasticsearch | awk '/Candidate:/{print $2}')"
if [[ -z "$CANDIDATE" || "$CANDIDATE" == "(none)" ]]; then
  echo "Impossible de déterminer une version candidate pour 'elasticsearch'." >&2
  exit 1
fi

sudo apt-get install -y "elasticsearch=${CANDIDATE}"
sudo apt-mark hold elasticsearch

echo "--- Vérification ---"
dpkg -s elasticsearch | grep -E '^(Package|Version|Status)'
id elasticsearch
