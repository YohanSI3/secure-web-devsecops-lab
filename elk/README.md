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

## Reste à faire

- Ingestion des logs existants (Nginx, fail2ban, PostgreSQL, Vault) via
  Filebeat/Logstash — parsing adapté à chaque format de log déjà en
  place.
- Dashboards Kibana : erreurs HTTP, IP suspectes, pics de requêtes.
- Alertes basiques (Kibana Alerting) sur ces mêmes signaux.
- Corrélation simple avec les détections fail2ban déjà en place (Phase 2).

## Scripts

```bash
./scripts/install-elasticsearch.sh
./scripts/deploy-elasticsearch-config.sh
```

## Vérification

*(sortie réelle à ajouter ici après exécution)*
