# ELK (Elasticsearch, Logstash, Kibana) — documentation technique

Phase 6 du `ToDo.md` (observabilité). Centralise les logs déjà produits
par chaque service de ce lab (Nginx, fail2ban, PostgreSQL, Vault) dans un
seul endroit interrogeable, avec des dashboards et des alertes
par-dessus. Pour le fonctionnement général de chaque composant
(pourquoi un moteur de recherche plutôt qu'une base relationnelle pour
des logs, rôle de chacun des trois), voir
[`Notes/elk/`](../Notes/elk/README.md).

## Choix de stack : ELK plutôt que Grafana+Loki

Alternative plus légère envisagée et écartée délibérément : Grafana +
Loki + Promtail, conçu précisément pour consommer moins de ressources
qu'Elasticsearch sur une centralisation de logs. Choix final : **ELK**
— stack historique de l'industrie, compétences (Kibana, requêtes
Lucene/KQL) plus largement recherchées que Loki/LogQL. Viable ici parce
que la VM dispose de marge confortable (13 Go de RAM libres sur 15 Go,
12 cœurs, 953 Go de disque — vérifié avant de se lancer, voir
« Vérification » plus bas), pas parce que l'alternative plus légère
n'avait pas de mérite.

## État actuel

Elasticsearch installé et configuré, pas encore démarré en conditions
réelles au moment de l'écriture de cette section — prochaine étape
« Vérification » ci-dessous. Logstash/Filebeat (ingestion), Kibana
(dashboards) et les alertes restent à faire, voir « Reste à faire ».

## Installation : dépôt apt officiel Elastic, ligne 9.x

[`scripts/install-elasticsearch.sh`](../scripts/install-elasticsearch.sh)
— même exception déjà documentée pour NodeSource/HashiCorp (Vault) :
Elasticsearch n'est pas empaqueté dans les dépôts Ubuntu, le dépôt
Elastic est le canal officiellement recommandé par l'éditeur. Ligne de
version **9.x** retenue (pas 8.x) après vérification directe des deux
dépôts (`curl` sur l'index `Packages` de chaque ligne, dernière version
publiée comparée) : 9.x est la ligne activement développée (dernier
patch constaté : 9.5.6), 8.x une ligne de maintenance plus ancienne
(8.19.25) — même logique que le choix de Node.js 24 (LTS active) plutôt
qu'une version plus ancienne.

## Configuration : étendre le fichier du paquet, jamais le remplacer

[`elk/elasticsearch-overrides.yml`](elasticsearch-overrides.yml),
**ajouté à la suite** de `/etc/elasticsearch/elasticsearch.yml` par
[`scripts/deploy-elasticsearch-config.sh`](../scripts/deploy-elasticsearch-config.sh)
(jamais en remplacement complet — voir « Bug réel » plus bas pour
pourquoi ce choix n'était pas évident au départ) :

- **Boucle locale uniquement** (`http.host: 127.0.0.1`) — même principe
  que PostgreSQL/Vault/Mailpit dans ce lab : Kibana et Logstash
  tourneront sur la même machine, aucune raison d'exposer Elasticsearch
  au réseau. Remplace explicitement `http.host: 0.0.0.0`, que
  l'auto-configuration de sécurité du paquet fixe par défaut.
- **`node.name`/`cluster.initial_master_nodes` cohérents entre eux** —
  le paquet bootstrape un cluster à un seul nœud en listant le nom de ce
  nœud (déduit du hostname de la machine par défaut) dans
  `cluster.initial_master_nodes`. Personnaliser `node.name` sans mettre à
  jour cette liste en même temps empêcherait le nœud de jamais achever
  son élection — les deux sont donc redéfinis ensemble.
- **Heap JVM fixé à 2 Go** (`jvm.options.d/heap.options`, `Xms`/`Xmx`
  identiques, pratique recommandée par Elastic pour éviter un
  redimensionnement en cours de fonctionnement) — confortable pour le
  volume de logs de ce lab, très en dessous de la RAM disponible. Ce
  fichier-ci est bien copié tel quel (pas étendu) : contrairement à
  `elasticsearch.yml`, le répertoire `jvm.options.d/` est un point
  d'extension vide par défaut, rien à y perdre en le remplaçant.

### Sécurité : auto-configuration du paquet laissée active, pas désactivée

Depuis Elasticsearch 8, le paquet active par défaut, dès le premier
démarrage, TLS (certificats auto-signés générés automatiquement) et un
utilisateur `elastic` avec mot de passe généré aléatoirement — affiché
**une seule fois** dans la sortie du premier démarrage. Volontairement
**pas désactivé** pour simplifier (ce que beaucoup de tutoriels font) :
cohérent avec l'approche du reste de ce lab (durcissement par défaut,
jamais retiré pour "faire simple" sans raison réelle).

**Leçon directement tirée de l'incident Vault**
([`vault/README.md`](../vault/README.md)) appliquée ici *avant* plutôt
qu'après coup : ce mot de passe généré au premier démarrage ne doit
**jamais** être collé dans une conversation ni laissé ouvert dans un
fichier suivi par un outil qui partage son contexte (éditeur, IDE) — à
sauvegarder immédiatement dans un gestionnaire de secrets local ou un
fichier hors du dépôt, jamais dans ce dépôt même temporairement.

**La consigne n'a pas suffi en pratique** : malgré l'avertissement
donné avant de lancer le script, le mot de passe `elastic` généré a
quand même été collé en clair dans la conversation de pilotage lors du
premier essai réel. Traité comme pour l'incident Vault : considéré
compromis, à réinitialiser (`elasticsearch-reset-password -u elastic`)
une fois l'installation stabilisée, plutôt que réutilisé silencieusement
— même si le risque réel reste faible ici (rien d'indexé encore,
instance jamais exposée au-delà de `127.0.0.1`). Confirme qu'un
avertissement préventif réduit le risque mais ne l'élimine pas — la
vérification après coup (ne jamais réutiliser une valeur exposée) reste
nécessaire dans tous les cas.

## Deux bugs réels, même cause racine : remplacer au lieu d'étendre

Les deux échecs réels rencontrés en déployant Elasticsearch pour la
première fois partagent exactement la même cause : un premier
`elasticsearch.yml` versionné dans ce dépôt **remplaçait entièrement**
(via `cp`) le fichier généré par le paquet à l'installation, au lieu de
l'étendre. Contrairement à PostgreSQL/Nginx (où les valeurs par défaut du
paquet suffisaient déjà, seul `pg_hba.conf` nécessitant un remplacement
complet et volontaire), le paquet Elasticsearch écrit **deux choses
importantes** dans son fichier de config par défaut, perdues par ce
remplacement.

### Bug 1 : `path.data`/`path.logs` perdus

`systemctl status elasticsearch` → `Main process exited,
code=exited, status=1/FAILURE` ; `journalctl -xeu elasticsearch` →
`AccessDeniedException: /usr/share/elasticsearch/logs`.

Le paquet crée bien, à l'installation, `/var/lib/elasticsearch` et
`/var/log/elasticsearch`, tous deux `elasticsearch:elasticsearch` — les
bons emplacements, avec les bonnes permissions, **déjà déclarés par
défaut** dans le fichier généré (`path.data: /var/lib/elasticsearch`,
`path.logs: /var/log/elasticsearch`, non commentés). En les écrasant avec
un fichier qui ne les redéclarait pas, Elasticsearch retombait sur un
chemin par défaut **relatif à son répertoire d'installation**
(`/usr/share/elasticsearch/logs`), qui n'existe pas et ne peut pas être
créé par le processus (tourne sous l'utilisateur `elasticsearch`, alors
que `/usr/share/elasticsearch` appartient à `root:root`).

### Bug 2 : auto-configuration de sécurité TLS écrasée, mots de passe orphelins

Correctif du bug 1 appliqué (ré-ajout de `path.data`/`path.logs` dans le
fichier de remplacement) — toujours en échec, cette fois plus loin dans
le démarrage (~30s de CPU consommée, plusieurs centaines de modules
chargés). Log réel dans `/var/log/elasticsearch/<cluster.name>.log`
(pas dans `journalctl`, qui ne pointe que vers ce fichier) :

```text
org.elasticsearch.ElasticsearchSecurityException: invalid configuration for xpack.security.transport.ssl -
[xpack.security.transport.ssl.enabled] is not set, but the following settings have been configured in
elasticsearch.yml : [xpack.security.transport.ssl.keystore.secure_password,xpack.security.transport.ssl.truststore.secure_password]
```

Cause réelle : l'installation du paquet déclenche une
**auto-configuration de sécurité** (certificats TLS auto-signés, mot de
passe de l'utilisateur `elastic`) qui écrit un bloc entier dans
`elasticsearch.yml` (`xpack.security.enabled`,
`xpack.security.transport.ssl.enabled`, `cluster.initial_master_nodes`
avec le hostname réel de la machine, `http.host: 0.0.0.0`...) en plus de
stocker des mots de passe chiffrés dans un keystore séparé
(`elasticsearch.keystore`, jamais touché par notre remplacement). En
écrasant `elasticsearch.yml` entièrement, le flag
`xpack.security.transport.ssl.enabled: true` disparaissait, mais le
keystore référençait toujours ses mots de passe — configuration
incohérente, refusée par une vérification de validité au démarrage
(volontaire côté Elasticsearch, pas un bug de leur part).

### Correctif définitif : ré-installation propre + extension plutôt que remplacement

Package purgé puis réinstallé (rien n'était encore indexé — repartir
d'un fichier auto-configuré propre était plus sûr que de reconstituer à
la main les bons réglages de sécurité). Fichier du dépôt renommé
[`elasticsearch-overrides.yml`](elasticsearch-overrides.yml) — ne
contient plus qu'un **bloc à ajouter**, jamais le fichier complet.
[`scripts/deploy-elasticsearch-config.sh`](../scripts/deploy-elasticsearch-config.sh)
retire d'abord, par motif (`sed`), les deux lignes précises que ce bloc
remplace (`http.host`, `cluster.initial_master_nodes` — nécessaire,
deux clés YAML identiques dans un même fichier provoqueraient une
erreur de parsing), puis ajoute le bloc à la fin du fichier existant —
tout le reste de l'auto-configuration (certificats, mots de passe,
`path.data`/`path.logs`) reste intact. Un marqueur en commentaire rend
le script idempotent (ne ré-applique pas le bloc si déjà présent).

Leçon générale qui en découle, au-delà d'Elasticsearch : avant de
remplacer intégralement un fichier de config généré par un paquet, lire
son contenu réel généré pour de vrai, pas supposé — ce que ses valeurs
par défaut couvrent déjà n'est pas toujours visible depuis l'extérieur
(ici, un mécanisme d'auto-configuration exécuté une seule fois, à
l'installation).

## Vérification

```text
$ curl -sk -u elastic:<mot-de-passe> https://127.0.0.1:9200
{
  "name" : "secure-web-lab-node-1",
  "cluster_name" : "secure-web-lab",
  "cluster_uuid" : "9BSzbnmMToWpqqJN6se9GA",
  "version" : {
    "number" : "9.5.6",
    "build_flavor" : "default",
    "build_type" : "deb",
    ...
  },
  "tagline" : "You Know, for Search"
}
```

`cluster_name`/`name` confirment que nos réglages ajoutés
(`elasticsearch-overrides.yml`) sont bien pris en compte par-dessus la
config auto-générée du paquet — pas seulement que le service démarre.
Mot de passe `elastic` réinitialisé une dernière fois après les
multiples installs/resets de cette session de débogage
(`elasticsearch-reset-password -u elastic`), pour repartir d'une valeur
dont l'historique de exposition dans la conversation est clos.

## Kibana : installation, enrôlement, clés de chiffrement

[`scripts/install-kibana.sh`](../scripts/install-kibana.sh) — même dépôt
apt Elastic que pour Elasticsearch, aucune nouvelle clé GPG/source à
ajouter (Kibana est publié dans la même ligne 9.x).

### Config : simple ajout, contrairement à Elasticsearch

[`elk/kibana-overrides.yml`](kibana-overrides.yml), ajouté par
[`scripts/deploy-kibana-config.sh`](../scripts/deploy-kibana-config.sh) —
vérifié avant d'écrire quoi que ce soit (leçon tirée directement des deux
bugs Elasticsearch ci-dessus) que le fichier par défaut livré par le
paquet ne contient que des exemples commentés, sans bloc auto-généré à
préserver. Un simple ajout en fin de fichier (`server.host:
"127.0.0.1"`, `server.port: 5601` — boucle locale uniquement, même
principe que le reste de ce lab) suffit donc, sans le risque de clé
dupliquée rencontré côté Elasticsearch.

### Enrôlement : jeton généré et consommé sans jamais être affiché

[`scripts/enroll-kibana.sh`](../scripts/enroll-kibana.sh) — génère un
jeton d'enrôlement côté Elasticsearch
(`elasticsearch-create-enrollment-token -s kibana`) et le passe
directement à `kibana-setup`, dans la même commande, sans jamais
l'afficher ni demander à l'opérateur de le manipuler. Contrairement au
mot de passe `elastic` (affiché une fois par nécessité, voir plus haut),
rien n'oblige ce jeton-ci à être vu par un humain — autant éviter
l'occasion de l'exposer par erreur. Les informations de connexion
résultantes (hôte Elasticsearch, identifiants de service) sont stockées
chiffrées dans le keystore propre à Kibana
(`/etc/kibana/kibana.keystore`), jamais dans `kibana.yml` en clair.

### Bug réel (mineur) : clés de chiffrement absentes désactivaient Alerting

Au premier démarrage, Kibana a généré une clé de chiffrement aléatoire
(`xpack.security.encryptionKey`) faute d'en trouver une configurée —
conséquence concrète, pas que théorique : `plugins.alerting` et
`plugins.actions` ont explicitement désactivé leurs API
(`APIs are disabled because the Encrypted Saved Objects plugin is
missing encryption key`). Problème réel pour ce lab : les alertes
Kibana sont un objectif explicite de cette phase (« Reste à faire »
ci-dessous), pas une fonctionnalité annexe qu'on peut se permettre de
perdre. Corrigé avec
[`scripts/generate-kibana-encryption-keys.sh`](../scripts/generate-kibana-encryption-keys.sh) —
même logique que l'enrôlement : les clés générées par
`kibana-encryption-keys generate -q` sont ajoutées directement à
`kibana.yml` sans jamais être affichées. Confirmé après coup (pas
supposé) : les logs ne montrent plus les avertissements de clé manquante,
et `plugins.alerting` initialise activement ses index d'alertes au
démarrage suivant (preuve que les API sont bien actives, pas seulement
que l'avertissement a disparu).

### Vérification

```text
$ curl -sk -o /dev/null -w "%{http_code}\n" http://127.0.0.1:5601
302
```

`302` : redirection non authentifiée vers la page de connexion,
comportement attendu pour un accès anonyme à la racine. Confirmé aussi
depuis un navigateur Windows via le transfert de boucle locale WSL2
(même mécanisme déjà observé avec Mailpit) : connexion réussie avec
l'utilisateur `elastic`. Pile Elasticsearch + Kibana fonctionnelle de
bout en bout.

## Filebeat + Logstash : ingestion des logs Nginx

Premier flux d'ingestion mis en place — fail2ban/PostgreSQL/Vault
suivront sur le même modèle, voir « Reste à faire » plus bas.

[`scripts/install-filebeat.sh`](../scripts/install-filebeat.sh) et
[`scripts/install-logstash.sh`](../scripts/install-logstash.sh) — même
dépôt apt Elastic déjà configuré pour Elasticsearch/Kibana, aucune
nouvelle source à ajouter.

### Filebeat : un seul rôle, lire et expédier

[`elk/filebeat.yml`](filebeat.yml), déployé par
[`scripts/deploy-filebeat-config.sh`](../scripts/deploy-filebeat-config.sh) —
remplacement complet du fichier par défaut (contrairement à
Elasticsearch, le défaut de Filebeat ne contient que des exemples
commentés, rien à perdre). Un `filestream` input sur les logs d'accès
Nginx des 3 vhosts, étiqueté (`fields: {service: nginx, log_type:
access}`) pour que Logstash sache quel filtre appliquer, sortie vers
Logstash (`output.logstash`) plutôt que directement Elasticsearch — voir
[`Notes/elk/logstash.md`](../Notes/elk/logstash.md) pour pourquoi
combiner les deux plutôt que Filebeat seul.

### Logstash : grok construit sur le vrai format, pas un format générique

[`elk/logstash-pipeline.conf`](logstash-pipeline.conf), déposé par
[`scripts/deploy-logstash-pipeline.sh`](../scripts/deploy-logstash-pipeline.sh)
dans `/etc/logstash/conf.d/` (déjà pointé par `pipelines.yml` du paquet,
aucune autre modification nécessaire). Le filtre `grok` est construit
directement à partir du `log_format security_log` réel de ce lab
([`nginx/conf.d/logging.conf`](../nginx/conf.d/logging.conf)), pas d'un
format Nginx générique — extrait `client_ip`, `request_path`,
`http_method`, `response_status`/`body_bytes_sent` (typés en entier),
`request_time` (typé en flottant), `ssl_info`, `user_agent`,
`http_referer`, `request_id`. Un filtre `date` reconvertit l'horodatage
Nginx (`dd/MMM/yyyy:HH:mm:ss Z`) en `@timestamp` UTC natif Elasticsearch.

### Compte Elasticsearch dédié à Logstash, jamais `elastic`

[`scripts/setup-logstash-elasticsearch-role.sh`](../scripts/setup-logstash-elasticsearch-role.sh) —
même principe que `vault_admin` (PostgreSQL) ou l'AppRole du backend
(Vault) : un rôle `secure-web-lab-logstash-writer` scopé, un utilisateur
`logstash_internal` dédié, jamais le compte superuser `elastic`. Mot de
passe généré et stocké directement dans le **keystore** de Logstash
(`logstash-keystore add`, jamais affiché ni manipulé par l'opérateur —
même logique que l'enrôlement Kibana).

## Bugs réels : une chaîne de cinq, chacun découvert en conditions réelles

Mettre Logstash en service a demandé de résoudre, dans l'ordre, cinq
problèmes réels distincts — aucun supposé ou corrigé sans vérification.
Dans l'ordre rencontré :

**1. Mauvais répertoire de paramètres pour l'outil `logstash-keystore`.**
Contrairement au service systemd (qui sait déjà où trouver
`/etc/logstash/`, voir `pipelines.yml`), l'outil CLI retombe par défaut
sur le répertoire d'installation (`/usr/share/logstash/config/`), pas
`/etc/logstash/` — `AccessDeniedException`/`NoSuchFileException` selon
que le répertoire cible existe ou non. Corrigé en passant
`--path.settings /etc/logstash` explicitement à chaque invocation de
l'outil.

**2. `/etc/logstash` n'est pas inscriptible par l'utilisateur `logstash`.**
Le paquet livre ce répertoire en `root:root` `755` — correct pour que le
service (qui tourne sous `logstash`) puisse **lire** sa config, mais pas
pour que ce même utilisateur puisse y **créer** un nouveau fichier
(le keystore). Corrigé en créant le keystore en root (`sudo` sans
`-u logstash`), puis `chown logstash:logstash` + `chmod 600` après coup —
même logique que les autres fichiers de config root-owned de ce lab.

**3. `--force` non reconnu par cette version de `logstash-keystore add`,
et noms de clé normalisés en minuscules.** `add LOGSTASH_ES_PASSWORD`
échoue sur `--force` (option inexistante ici) et, une fois retirée,
stocke la clé comme `logstash_es_password` (minuscules) même si
l'argument passé était en majuscules — constaté en pratique, pas
documenté nulle part de façon évidente. `elk/logstash-pipeline.conf`
référence donc `${logstash_es_password}`, pas la casse qu'on attendrait
intuitivement.

**4. Bug d'idempotence dans ce script lui-même : mots de passe
désynchronisés entre Elasticsearch et le keystore.** Une première version
régénérait un mot de passe aléatoire **à chaque exécution** et le
poussait côté Elasticsearch, sans revérifier si le keystore avait déjà
une entrée — dès le second lancement, Elasticsearch attendait le
nouveau mot de passe tandis que le keystore gardait encore l'ancien.
Symptôme : `401 unable to authenticate user [logstash_internal]` côté
Logstash. Corrigé en ne générant/poussant un nouveau mot de passe que
lorsque le keystore n'a **pas encore** l'entrée — les deux changent
ensemble, jamais l'un sans l'autre, ou aucun des deux.

**5. Deux privilèges cluster manquants, découverts l'un après l'autre.**
Un rôle Elasticsearch en écriture sur un index précis ne suffit pas pour
le plugin de sortie Elasticsearch de Logstash, qui fait deux choses
supplémentaires à chaque démarrage, indépendamment de toute écriture
réelle de document :
  - un **healthcheck** sur l'endpoint racine du cluster (`GET /`),
    nécessitant le privilège cluster `monitor` ;
  - une tentative d'**installation de son modèle d'index par défaut**
    (`ecs-logstash`), nécessitant `manage_index_templates` — traité comme
    une erreur **fatale** de bootstrap si refusé
    (`Failed to bootstrap... Pipeline "main" is going to shut down`),
    même si ce modèle ne s'appliquerait jamais à l'index personnalisé de
    ce lab (`secure-web-lab-logs-*` ne correspond pas au motif par défaut
    `logstash-*`). Pas une option désactivable côté configuration du
    plugin — un prérequis du bootstrap, qu'on en ait besoin ou non.

  Sans ces deux privilèges, systemd redémarrait Logstash en boucle
  (observé : `restart counter` grimpant à 18) sans jamais rester stable —
  chaque tentative échouait de la même façon, à chaque fois après avoir
  déjà accepté des connexions Beats pendant quelques secondes, rendant le
  symptôme trompeur (on pouvait croire le pipeline "presque" fonctionnel).
  Corrigé en ajoutant `"cluster": ["monitor", "manage_index_templates"]`
  au rôle — toujours pas `manage`/`all`, qui irait bien au-delà du
  nécessaire.

## Vérification

```text
$ for i in 1 2 3; do curl ... "$BASE/"; done; curl ... "$BASE/does-not-exist"
$ curl -sk -u elastic:<mot-de-passe> "https://127.0.0.1:9200/secure-web-lab-logs-*/_search?pretty&size=3"
{
  "hits": {
    "total": { "value": 16, "relation": "eq" },
    "hits": [
      {
        "_index": "secure-web-lab-logs-2026.11.11",
        "_source": {
          "client_ip": "127.0.0.1",
          "http_method": "POST",
          "request_path": "/api/auth/register",
          "response_status": 201,
          "body_bytes_sent": 55,
          "request_time": 0.185,
          "ssl_info": "TLSv1.3/TLS_AES_256_GCM_SHA384",
          "request_id": "5c51eb392024ba11339957157c1a8b0f",
          "service": "nginx",
          "@timestamp": "2026-11-11T16:38:02.000Z"
        }
      }
    ]
  }
}
```

`response_status`/`body_bytes_sent` bien typés en entiers,
`request_time` en flottant (pas des chaînes de caractères) — confirme
que le mapping dynamique d'Elasticsearch a correctement interprété les
types déclarés par le filtre `grok` (`:int`/`:float`), pas juste indexé
du texte brut. `@timestamp` en UTC (`16:38:02Z`) alors que
l'horodatage Nginx d'origine était en CET (`17:38:02 +0100`) — confirme
que le filtre `date` a bien effectué la conversion de fuseau horaire,
pas simplement recopié l'heure locale telle quelle.

**Pipeline Nginx → Filebeat → Logstash → Elasticsearch fonctionnel de
bout en bout**, confirmé par une vraie recherche après une vraie
requête HTTP — pas en relisant la config à froid. `NRestarts=0` sur le
service Logstash après le dernier correctif, confirmant la fin de la
boucle de redémarrage.

## Filebeat + Logstash : extension à fail2ban, PostgreSQL, Vault

Même modèle que Nginx ci-dessus — un input Filebeat par source, un bloc
de filtre Logstash par source dans le même pipeline
([`elk/logstash-pipeline.conf`](logstash-pipeline.conf)), une sortie
Elasticsearch partagée (`secure-web-lab-logs-%{+YYYY.MM.dd}`, choix
délibéré pour permettre la corrélation entre services dans Kibana plutôt
qu'un index par service).

- **fail2ban** — `filestream` sur `/var/log/fail2ban.log`.
- **PostgreSQL** — `filestream` sur
  `/var/log/postgresql/postgresql-*-main.log`, grok construit sur le
  `log_line_prefix` réel de ce lab (`%m [%p] %q%u@%d %h `, voir
  [`postgresql/README.md`](../postgresql/README.md)).
- **Vault** — `journald` (`units: [vault.service]`, `seek: tail`) plutôt
  que `filestream` : Vault n'écrit jamais dans un fichier de log, voir
  [`vault/README.md`](../vault/README.md).

### Bug réel (nouveau) : alignement en colonnes dans les logs fail2ban casse le grok sur 100% des lignes

Après déploiement, confirmé par une vraie agrégation Elasticsearch
(`service: fail2ban`, agrégation par présence du tag
`_grokparsefailure`) : **121 documents en échec, 0 en succès** — pas un
cas limite, la totalité des lignes fail2ban ingérées jusque-là.

Cause : fail2ban aligne ses colonnes avec un nombre **variable**
d'espaces, pas un espace unique, pour compenser les noms de module de
longueur différente (`filter`, `jail`, `actions`, `filtersystemd`...) et
les noms de niveau de longueur différente (`INFO`, `NOTICE`,
`WARNING`...) :

```text
2026-11-11 19:36:16,706 fail2ban.filter         [205]: INFO    [nginx-404-flood] Found 172.23.201.189 - 2026-11-11 19:36:16
2026-11-11 19:36:17,162 fail2ban.actions        [205]: NOTICE  [nginx-404-flood] Ban 172.23.201.189
```

Le motif `grok` initial utilisait un espace littéral entre le nom du
module et `[PID]`, et entre le niveau et le message — qui ne matche
qu'un seul espace, jamais plusieurs. Corrigé en remplaçant ces deux
espaces littéraux par `\s+` :

```
fail2ban\.%{WORD:fb_module}\s+\[%{NUMBER:fb_pid}\]:\s+%{WORD:fb_level}\s+%{GREEDYDATA:fb_message}
```

Les 121 documents déjà indexés avant ce correctif restent marqués
`_grokparsefailure` (Logstash ne retraite jamais rétroactivement des
documents déjà écrits) — sans conséquence réelle ici (aucun dashboard ni
alerte ne s'appuie encore sur ces données historiques), mais un rappel
que corriger un filtre ne répare pas le passé, seulement le flux à venir.

### PostgreSQL : la limite déjà documentée se confirme, sous une forme légèrement différente de ce qui était anticipé

L'exception documentée plus haut dans ce fichier (lignes sans `user@db`
pour les processus d'arrière-plan) existe bien, mais la cause réelle
observée est différente de celle supposée au moment d'écrire le motif :
pas des processus internes du moteur (checkpointer, autovacuum) mais des
lignes de **connexion/déconnexion** où PostgreSQL n'a pas encore résolu
l'utilisateur/la base, et les affiche littéralement entre crochets :

```text
2026-11-19 ... [unknown]@[unknown] 127.0.0.1 LOG:  connection received: host=127.0.0.1 port=...
```

`%{USERNAME}`/`%{IPORHOST}` ne matchent pas les crochets littéraux — ces
lignes restent en `_grokparsefailure`, acceptable pour l'objectif de ce
lab (voir plus haut), mais pour une raison différente de celle écrite
initialement dans le commentaire du filtre. Les lignes qui comptent
réellement pour la sécurité (`FATAL: password authentication failed`,
`FATAL: no pg_hba.conf entry...`) ont toujours un `user@db` et un `host`
résolus et complets, donc matchent sans problème — confirmé ci-dessous.

### Vérification réelle (fail2ban, PostgreSQL, Vault)

Événements générés réellement (pas simulés) : six tentatives
`PGPASSWORD=wrongpass psql -U secure_web_lab_app ...` (rôle réel
confirmé via `\du` avant le test), un déclenchement réel de la jail
`nginx-404-flood` (12 requêtes 404 depuis l'IP d'interface réelle de la
VM, pas `127.0.0.1` — exempté par `ignoreself`), et un redémarrage réel
de `vault.service`.

```text
// service: vault
"vault_level": "INFO",
"vault_message": "core: updated local kmip enabled: prefix=local/ currentMonth=\"2026-11-11 18:23:14...\"",
"@timestamp": "2026-11-11T18:23:14.157Z"   // horodatage source : 19:23:14.157+0100 (CET) -- conversion UTC confirmée
```

```text
// service: postgresql
"pg_level": "FATAL",
"pg_user": "secure_web_lab_app",
"pg_db": "secure_web_lab",
"pg_host": "127.0.0.1",
"pg_tz": "CET",
"pg_message": "password authentication failed for user \"secure_web_lab_app\""
```

```text
// service: fail2ban -- après correctif du bug d'alignement ci-dessus
"fb_module": "actions",
"fb_level": "NOTICE",
"fb_jail": "nginx-404-flood",
"banned_ip": "172.23.201.189",
"fb_message": "[nginx-404-flood] Ban 172.23.201.189"
```

`fb_jail`/`banned_ip` (champ dédié, extrait par un second `grok` imbriqué
qui ne s'exécute que si `fb_message` contient `Ban `) sont précisément
les champs destinés à la corrélation avec les autres services —
objectif explicite de cette phase, voir « Reste à faire ».

**Ingestion des quatre sources (Nginx, fail2ban, PostgreSQL, Vault)
fonctionnelle de bout en bout**, confirmée par de vrais événements réels
plutôt que supposée depuis la configuration.

## Kibana : dashboards, alerting, corrélation

Construits à la main dans l'UI Kibana (pas via l'API Saved Objects) —
choix délibéré pour ce tour : plus proche de l'usage réel de Kibana au
quotidien, au prix de ne pas être reproductible depuis le dépôt seul. Vue
de données créée en premier (**Stack Management → Data Views**) :
`secure-web-lab-logs` sur le motif `secure-web-lab-logs-*`, champ
d'horodatage `@timestamp` — confirmée dans Discover avant de construire
quoi que ce soit dessus (tous les champs des quatre services présents :
`client_ip`, `response_status`, `banned_ip`, `fb_jail`, `pg_level`...).

**Piège rencontré en vérifiant** : `pg_level` semblait absent de Discover
en fenêtre « 7 derniers jours ». Pas un bug — les six événements
PostgreSQL réels avec `pg_level` renseigné dataient du 11 novembre,
hors de cette fenêtre glissante depuis le 19 novembre. Élargir à
« 30 derniers jours » l'a fait réapparaître. Rappel direct de la
différence entre *champ absent du mapping* et *champ sans valeur dans
les documents actuellement filtrés* — Kibana distingue bien les deux
(section « Champs vides » dans la liste des champs de Discover).

### Dashboard : 4 panneaux, tableau de bord `Sécurité — secure-web-lab`

- **Erreurs HTTP (4xx/5xx)** — histogramme temporel, `response_status >= 400`.
- **IP suspectes (404 répétées)** — tableau Lens, top `client_ip.keyword`
  filtré sur `response_status: 404`.
- **Volume de requêtes Nginx (détection de pics)** — histogramme temporel,
  `fields.service: nginx`, sans filtre de statut.
- **Bannissements fail2ban (liste)** — **pas** une visualisation Lens :
  une recherche Discover enregistrée (`fields.service: "fail2ban" and
  banned_ip: *`, colonnes `fb_jail`/`banned_ip`, triée par `@timestamp`
  décroissant), intégrée au tableau de bord via « Ajouter depuis la
  bibliothèque ». Tentative initiale ratée documentée ci-dessous.

**Bug réel (configuration, pas code) : mauvais type de panneau pour une
liste d'événements bruts.** Premier essai du panneau de bannissements en
tableau Lens avec `@timestamp` glissé en ligne — Lens a sa propre
interprétation de ce que représente un champ de date placé en
« Lignes » : il le transforme en histogramme temporel à intervalle fixe
(ici 12h) et produit le **produit cartésien** de chaque intervalle avec
chaque combinaison `(fb_jail, banned_ip)`, donnant un tableau énorme
rempli de lignes `(null)` pour chaque créneau sans événement — parce que
les tableaux Lens reposent sur une agrégation, jamais sur une simple
liste de documents bruts. Corrigé en remplaçant ce panneau par une
recherche Discover enregistrée (modèle document-par-document, pas
agrégé) — le bon outil pour « lister les vrais événements », pas un
mauvais réglage d'un bon outil.

**Résultat réel (vérifié, pas supposé)** : panneau « IP suspectes »
montre `172.23.201.189` en tête avec 36 occurrences (cumul des trois
déclenchements réels de `nginx-404-flood` de cette session) ; panneau
« Bannissements fail2ban » liste deux bannissements réels, tous deux
pour cette même IP, même jail (`nginx-404-flood`) — la même IP apparaît
dans les deux panneaux, côte à côte, sans jointure automatisée : exactement
la « corrélation simple » visée par cette phase (voir `ToDo.md`), un
humain regardant le tableau de bord relie directement les deux.

### Alerting : licence Gold requise pour le connecteur Email, non disponible sur ce lab

Tentative initiale : connecteur **Email**, réutilisant Mailpit déjà en
place pour `app/backend`
([`app/backend/src/mail.js`](../app/backend/src/mail.js) : SMTP
`127.0.0.1:1025`, sans authentification ni TLS). Bloqué à la création du
connecteur : Kibana exige une **licence Gold** (payante) pour le
connecteur Email — seuls **Index** et **Server log** restent disponibles
sur la licence Basic (gratuite) de ce lab. Repli sur le connecteur
**Index** : chaque déclenchement de la règle écrit un document réel dans
un nouvel index dédié (`secure-web-lab-alerts`), plutôt qu'une simple
ligne de log serveur — choisi parce qu'il reste interrogeable/affichable
après coup (contrairement à une ligne de log texte), plus proche d'un
vrai pipeline d'alerting qui conserve une piste d'audit.

Règle créée (**Stack Management → Rules**, type **Elasticsearch query**) :

- Requête KQL : `fields.service: "fail2ban" and banned_ip: *`
- Seuil : `count() > 0` sur les 1 dernières minutes, vérifié toutes les minutes
- Fréquence de déclenchement de l'action : **« On status change »** —
  l'action ne se redéclenche pas à chaque vérification tant que
  l'alerte reste active pour le même événement, seulement au passage
  inactif → actif (et inversement au passage actif → récupéré).
- Action : connecteur **Index**, document contenant `rule.name`,
  `context.title`, `context.value`, `date` (variables de gabarit
  fournies par ce type de règle).

**Vérifié avec un vrai bannissement déclenché en conditions réelles**
(pas simulé) :

```json
{
  "rule_name": "fail2ban - nouvelle IP bannie",
  "context_title": "rule 'fail2ban - nouvelle IP bannie' matched query",
  "context_value": "1",
  "date": "2026-11-19T00:38:14.544Z"
}
```

Document réellement présent dans `secure-web-lab-alerts` après un
bannissement réel de `nginx-404-flood` — confirme la chaîne complète
détection fail2ban → ingestion Logstash → règle Kibana → action Index,
pas seulement que la règle passe « active » dans l'UI (vérifié
séparément aussi : statut `active` puis `recovered` dans l'onglet
Alertes de la règle, cohérent avec la fenêtre glissante d'une minute qui
expire après le bannissement).

**Phase 6 (observabilité) terminée** : ingestion des quatre sources,
dashboard, alerting, et corrélation simple tous vérifiés avec des
événements réels plutôt que supposés depuis la configuration.

## Scripts

```bash
./scripts/install-elasticsearch.sh
./scripts/deploy-elasticsearch-config.sh
./scripts/install-kibana.sh
./scripts/deploy-kibana-config.sh
./scripts/enroll-kibana.sh
./scripts/generate-kibana-encryption-keys.sh
./scripts/install-filebeat.sh
./scripts/install-logstash.sh
./scripts/deploy-filebeat-config.sh
./scripts/deploy-logstash-pipeline.sh
./scripts/setup-logstash-elasticsearch-role.sh
```

Dashboards, règle d'alerting et recherche enregistrée construits à la
main dans l'UI Kibana (voir « Kibana : dashboards, alerting,
corrélation » ci-dessus) — pas de script pour cette partie, choix
assumé pour cette phase.
