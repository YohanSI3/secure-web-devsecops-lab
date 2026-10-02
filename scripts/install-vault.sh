#!/usr/bin/env bash
# Installe HashiCorp Vault (OSS) depuis le dépôt apt officiel HashiCorp.
# Exception documentée au principe "dépôts officiels Ubuntu uniquement"
# appliqué à Nginx/PostgreSQL/fail2ban (voir vault/README.md) -- même
# logique que scripts/install-nodejs.sh pour NodeSource : Vault n'est pas
# empaqueté dans les dépôts Ubuntu, le dépôt HashiCorp est le canal
# officiellement recommandé par l'éditeur lui-même, pas un PPA tiers non
# maîtrisé.
set -euo pipefail

KEYRING=/usr/share/keyrings/hashicorp-archive-keyring.gpg

sudo apt-get update
sudo apt-get install -y gnupg

# Téléchargement et import de la clé séparés (pas un `curl | gpg` direct) :
# même raisonnement que scripts/install-nodejs.sh pour curl-pipe-bash --
# un flux direct ne laisse rien à inspecter entre réception et usage.
KEY_FILE="$(mktemp)"
curl -fsSL https://apt.releases.hashicorp.com/gpg -o "$KEY_FILE"
sudo gpg --batch --yes --dearmor -o "$KEYRING" "$KEY_FILE"
rm -f "$KEY_FILE"

echo "deb [signed-by=${KEYRING}] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null

sudo apt-get update

CANDIDATE="$(apt-cache policy vault | awk '/Candidate:/{print $2}')"
if [[ -z "$CANDIDATE" || "$CANDIDATE" == "(none)" ]]; then
  echo "Impossible de déterminer une version candidate pour 'vault'." >&2
  exit 1
fi

sudo apt-get install -y "vault=${CANDIDATE}"
sudo apt-mark hold vault

echo "--- Vérification ---"
vault version
id vault
