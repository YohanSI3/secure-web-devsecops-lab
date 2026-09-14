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

curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | sudo -E bash -
sudo apt-get install -y nodejs

# Empêche apt upgrade/dist-upgrade de faire dériver la version
# silencieusement, même logique que scripts/install-nginx.sh.
sudo apt-mark hold nodejs

echo "--- Vérification ---"
node -v
npm -v
