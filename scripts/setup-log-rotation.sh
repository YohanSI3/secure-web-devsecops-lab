#!/usr/bin/env bash
# Configure la rotation des logs Nginx pour ce lab. Deux configs
# logrotate séparées, chacune sur son propre périmètre de fichiers pour
# éviter que l'une ne se dispute les mêmes fichiers que l'autre (logrotate
# ignore silencieusement un fichier déjà "revendiqué" par une config
# traitée plus tôt dans /etc/logrotate.d/, par ordre alphabétique) :
#   - /etc/logrotate.d/nginx (livré par le paquet Ubuntu) restreint aux
#     deux logs génériques access.log/error.log (son glob par défaut,
#     /var/log/nginx/*.log, couvrirait sinon aussi nos logs par-site) ;
#   - nginx/logrotate/secure-web-lab.conf (ce dépôt), symlinké dans
#     /etc/logrotate.d/, gère exclusivement nos logs par-site.
# Voir nginx/README.md#rotation-de-logs et Notes/nginx/rotation-logs/.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STOCK_CONF="/etc/logrotate.d/nginx"
EXPECTED_BROAD_LINE='/var/log/nginx/*.log {'
NARROWED_LINE='/var/log/nginx/access.log /var/log/nginx/error.log {'

if [[ -f "$STOCK_CONF" ]]; then
  FIRST_LINE="$(head -n1 "$STOCK_CONF")"
  if [[ "$FIRST_LINE" == "$EXPECTED_BROAD_LINE" ]]; then
    BACKUP="${STOCK_CONF}.bak-$(date +%Y%m%d%H%M%S)"
    sudo cp "$STOCK_CONF" "$BACKUP"
    sudo sed -i "1s#.*#${NARROWED_LINE}#" "$STOCK_CONF"
    echo "Glob de ${STOCK_CONF} restreint aux logs génériques (sauvegarde : ${BACKUP})."
  elif [[ "$FIRST_LINE" == "$NARROWED_LINE" ]]; then
    echo "${STOCK_CONF} déjà restreint — rien à faire."
  else
    echo "ATTENTION: première ligne de ${STOCK_CONF} inattendue :" >&2
    echo "  ${FIRST_LINE}" >&2
    echo "Ni le motif large ni le motif restreint attendus — vérifier manuellement." >&2
  fi
else
  echo "${STOCK_CONF} absent — rien à restreindre."
fi

sudo ln -sf "${REPO_ROOT}/nginx/logrotate/secure-web-lab.conf" /etc/logrotate.d/secure-web-lab-nginx

echo "--- Vérification (dry-run, ne modifie rien) ---"
sudo logrotate -d /etc/logrotate.d/secure-web-lab-nginx
