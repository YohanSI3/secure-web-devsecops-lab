#!/usr/bin/env bash
# Installe fail2ban et relie la config versionnée de ce dépôt
# (fail2ban/jail.local, fail2ban/filter.d/) à /etc/fail2ban/, par symlink,
# même modèle que scripts/deploy-nginx-config.sh. Voir fail2ban/README.md
# pour les choix (jails, seuils, action de bannissement) et Notes/fail2ban/
# pour le fonctionnement général.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v fail2ban-client >/dev/null; then
  sudo apt-get update
  sudo apt-get install -y fail2ban
fi

sudo mkdir -p /etc/fail2ban/filter.d
sudo ln -sf "${REPO_ROOT}/fail2ban/jail.local" /etc/fail2ban/jail.local
for f in "${REPO_ROOT}"/fail2ban/filter.d/*.conf; do
  sudo ln -sf "$f" "/etc/fail2ban/filter.d/$(basename "$f")"
done

if [[ ! -f /etc/fail2ban/filter.d/nginx-botsearch.conf ]]; then
  echo "ATTENTION: filtre 'nginx-botsearch' introuvable dans /etc/fail2ban/filter.d/" >&2
  echo "(normalement livré avec le paquet fail2ban) — la jail 'nginx-botsearch'" >&2
  echo "ne démarrera pas tant que ce filtre n'est pas présent." >&2
fi

sudo systemctl restart fail2ban

echo "--- Auto-test du filtre personnalisé nginx-404-flood ---"
TMP_LOG="$(mktemp)"
echo '10.0.0.1 - - [10/Sep/2026:12:00:00 +0000] "GET /wp-login.php HTTP/1.1" 404 146 "-" "curl/8.0"' > "$TMP_LOG"
fail2ban-regex "$TMP_LOG" "${REPO_ROOT}/fail2ban/filter.d/nginx-404-flood.conf" || true
rm -f "$TMP_LOG"

echo "--- Vérification ---"
sudo fail2ban-client status
sudo fail2ban-client status nginx-botsearch
sudo fail2ban-client status nginx-404-flood
