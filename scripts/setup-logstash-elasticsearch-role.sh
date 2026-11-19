#!/usr/bin/env bash
# Crée un rôle et un utilisateur Elasticsearch dédiés à Logstash, en
# écriture seule sur les index de ce lab -- jamais le compte superuser
# elastic (même principe que vault_admin côté PostgreSQL, ou l'AppRole
# du backend côté Vault : un compte de service scopé, pas un accès
# administrateur réutilisé par commodité). Mot de passe généré puis
# stocké directement dans le keystore Logstash, jamais affiché -- même
# logique que l'enrôlement Kibana (scripts/enroll-kibana.sh).
#
# Nécessite ELASTIC_PASSWORD (mot de passe du compte elastic) exporté
# dans le shell courant avant exécution.
set -euo pipefail

if [[ -z "${ELASTIC_PASSWORD:-}" ]]; then
  echo "Exporter ELASTIC_PASSWORD avant de lancer ce script." >&2
  exit 1
fi

ES="https://127.0.0.1:9200"
CA=/etc/elasticsearch/certs/http_ca.crt
ROLE_NAME="secure-web-lab-logstash-writer"
USER_NAME="logstash_internal"

# --path.settings explicite : sans lui, l'outil CLI (contrairement au
# service systemd, qui le sait déjà -- voir pipelines.yml déjà dans
# /etc/logstash/) retombe sur le répertoire d'installation
# (/usr/share/logstash/config/), pas /etc/logstash/, et échoue (chemin
# non inscriptible par l'utilisateur logstash).
LS_SETTINGS="--path.settings /etc/logstash"

# Deux privilèges cluster distincts, tous deux découverts nécessaires en
# pratique (voir elk/README.md pour le détail des deux incidents) :
# - "monitor" : le plugin de sortie Elasticsearch fait un healthcheck sur
#   l'endpoint racine du cluster à chaque démarrage.
# - "manage_index_templates" : ce même plugin tente d'installer son
#   modèle d'index par défaut ("ecs-logstash") au bootstrap, et traite un
#   échec comme fatal ("Failed to bootstrap... going to shut down") --
#   même si ce modèle ne s'appliquerait jamais à notre index personnalisé
#   ("secure-web-lab-logs-*", qui ne matche pas son motif par défaut
#   "logstash-*"). Pas optionnel du point de vue du plugin, qu'on l'utilise
#   réellement ou non. Les deux restent read-only/structurels (pas de
#   privilège cluster "manage"/"all", qui irait bien au-delà du
#   nécessaire). Idempotent par construction (PUT-like), safe à rejouer.
curl -sk --cacert "$CA" -u "elastic:${ELASTIC_PASSWORD}" -X POST "${ES}/_security/role/${ROLE_NAME}" \
  -H 'Content-Type: application/json' -d '{
    "cluster": ["monitor", "manage_index_templates"],
    "indices": [
      { "names": ["secure-web-lab-logs-*"], "privileges": ["create_index", "write", "manage"] }
    ]
  }'
echo

if [[ ! -f /etc/logstash/logstash.keystore ]]; then
  # Pas de mot de passe sur le keystore lui-même -- l'accès est déjà
  # contrôlé par les permissions du système de fichiers, pas par un
  # second secret à gérer en plus pour un gain marginal à cette échelle.
  echo y | sudo /usr/share/logstash/bin/logstash-keystore ${LS_SETTINGS} create
  sudo chown logstash:logstash /etc/logstash/logstash.keystore
  sudo chmod 600 /etc/logstash/logstash.keystore
fi

# Bug réel corrigé ici (voir elk/README.md) : le mot de passe côté
# Elasticsearch et celui stocké dans le keystore Logstash doivent
# changer **ensemble**, jamais l'un sans l'autre -- une première version
# de ce script régénérait un mot de passe aléatoire à chaque exécution
# et le poussait côté Elasticsearch sans jamais revérifier le keystore,
# qui restait sur l'ancienne valeur dès le second lancement
# (401 "unable to authenticate" côté Logstash). Nom de clé en
# minuscules : logstash-keystore normalise automatiquement le nom passé
# à `add` ("LOGSTASH_ES_PASSWORD" en argument est bien stocké comme
# "logstash_es_password", constaté en pratique) --
# elk/logstash-pipeline.conf référence donc ${logstash_es_password}.
if sudo /usr/share/logstash/bin/logstash-keystore ${LS_SETTINGS} list 2>/dev/null | grep -qx "logstash_es_password"; then
  echo "logstash_es_password déjà présente dans le keystore -- mot de passe Elasticsearch existant laissé inchangé (les deux doivent rester synchronisés ; voir --rotate pour un vrai changement coordonné, pas encore scripté)."
else
  LOGSTASH_PASSWORD="$(openssl rand -hex 24)"

  curl -sk --cacert "$CA" -u "elastic:${ELASTIC_PASSWORD}" -X POST "${ES}/_security/user/${USER_NAME}" \
    -H 'Content-Type: application/json' -d "{
      \"password\": \"${LOGSTASH_PASSWORD}\",
      \"roles\": [\"${ROLE_NAME}\"],
      \"full_name\": \"Logstash (secure-web-lab)\"
    }"
  echo

  echo "${LOGSTASH_PASSWORD}" | sudo /usr/share/logstash/bin/logstash-keystore ${LS_SETTINGS} add logstash_es_password --stdin

  unset LOGSTASH_PASSWORD
fi

echo "--- Vérification (pas le mot de passe lui-même) ---"
sudo -u logstash /usr/share/logstash/bin/logstash-keystore ${LS_SETTINGS} list
