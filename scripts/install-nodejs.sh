#!/usr/bin/env bash
# Installe Node.js (ligne LTS active, actuellement 24.x "Krypton") depuis
# le dépôt officiel NodeSource. Exception documentée au principe "dépôts
# officiels Ubuntu uniquement" appliqué à Nginx (voir
# Notes/nodejs/installation/README.md) : le paquet `nodejs` des dépôts
# Ubuntu 24.04 est une version ancienne, déjà en fin de vie ou proche,
# inadaptée à un développement actif -- NodeSource est le canal de
# distribution officiellement recommandé par le projet Node.js lui-même
# pour les systèmes basés sur apt, pas un PPA tiers non maîtrisé.
set -euo pipefail

NODE_MAJOR=24

# Téléchargement et exécution séparés (pas un `curl | bash` direct) :
# repéré par le SAST (Semgrep, bash.curl.security.curl-pipe-bash) comme
# schéma à risque -- un pipe direct exécute le flux au fur et à mesure
# qu'il arrive, sans possibilité d'inspection ni de coupure nette entre
# "ce qui a été reçu" et "ce qui s'exécute". Ça ne change pas le modèle de
# confiance de fond (NodeSource reste la source, toujours en HTTPS, voir
# Notes/nodejs/README.md) : aucune vérification cryptographique de
# signature n'est faite pour autant, seule l'exécution en flux continu est
# supprimée.
SETUP_SCRIPT="$(mktemp)"
curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" -o "$SETUP_SCRIPT"
sudo -E bash "$SETUP_SCRIPT"
rm -f "$SETUP_SCRIPT"

sudo apt-get install -y nodejs

# Empêche apt upgrade/dist-upgrade de faire dériver la version
# silencieusement, même logique que scripts/install-nginx.sh.
sudo apt-mark hold nodejs

echo "--- Vérification ---"
node -v
npm -v
