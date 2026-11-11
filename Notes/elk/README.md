# ELK : Elasticsearch, Logstash, Kibana

## Contexte

Phase 6 du `ToDo.md` (observabilité). Jusqu'ici, chaque service de ce lab
journalise dans son propre fichier, avec son propre format : logs Nginx
(`Notes/nginx/journalisation/`), fail2ban (`Notes/fail2ban/`), PostgreSQL
(`Notes/postgresql/`), Vault. Utile service par service, mais aucune vue
d'ensemble — répondre à "quelles IP ont été actives sur plusieurs
services à la fois cette heure-ci ?" demande de croiser plusieurs
fichiers à la main. ELK répond à ce problème précis : centraliser,
indexer, puis interroger/visualiser tous ces logs depuis un seul endroit.
Les choix concrets pour ce lab sont dans
[`elk/README.md`](../../elk/README.md).

## Sommaire

- [`elasticsearch.md`](elasticsearch.md) — le moteur de recherche/stockage :
  documents et index, pourquoi un moteur de recherche plutôt qu'une base
  relationnelle pour des logs, modèle de nœud/cluster à une seule
  machine, auto-configuration de sécurité (TLS, mot de passe superuser),
  dimensionnement du tas JVM.
- [`logstash.md`](logstash.md) — la couche d'ingestion/transformation :
  pipeline entrée/filtre/sortie, filtres `grok`, différence avec
  Filebeat et quand combiner les deux. *Pas encore déployé dans ce lab
  au moment de l'écriture — note conceptuelle en préparation de cette
  étape.*
- [`kibana.md`](kibana.md) — la couche de visualisation/requête :
  rôle vis-à-vis d'Elasticsearch, jetons d'enrôlement, keystore propre,
  clés de chiffrement internes et pourquoi leur absence désactive
  silencieusement des fonctionnalités entières.

## Les trois rôles, et comment ils s'enchaînent

Le nom "ELK" désigne trois logiciels distincts, chacun avec un rôle
précis dans une chaîne : **Elasticsearch** stocke et indexe,
**Logstash**/**Filebeat** collectent et transforment les logs bruts
avant de les envoyer à Elasticsearch, **Kibana** interroge Elasticsearch
pour construire visualisations, tableaux de bord et alertes. Détail de
chacun dans son propre fichier ci-dessus.

## Pourquoi un moteur de recherche pour des logs

Une ligne de log est un petit texte daté, produit en grand volume, qu'on
veut pouvoir filtrer (`status >= 500`), compter (combien de 404 par
IP ?), et trier par le temps, souvent sans savoir à l'avance quelle
combinaison de critères on cherchera. Un moteur de recherche en texte
intégral est pensé pour ce schéma d'accès (recherche flexible, ad hoc, à
grande échelle), là où une base relationnelle classique brille plutôt
sur des relations stables entre entités et des transactions — deux
outils pensés pour deux problèmes différents, pas un remplacement l'un
de l'autre. Détail du fonctionnement interne dans
[`elasticsearch.md`](elasticsearch.md).

## Keystore vs fichier de config en clair : un principe partagé par E et K

Elasticsearch et Kibana ont chacun leur **propre** keystore — un fichier
qui stocke des valeurs sensibles chiffrées (mots de passe, jetons de
service), séparé du fichier de configuration principal
(`elasticsearch.yml`, `kibana.yml`) qui reste en texte clair. Même
principe que Vault lui-même, à une échelle plus locale : ne jamais faire
cohabiter un secret et sa configuration générale dans le même fichier en
clair. Conséquence pratique à connaître : un fichier de config qui ne
contient aucun mot de passe visible ne veut pas dire qu'aucune
authentification n'est en jeu, seulement qu'elle est stockée ailleurs,
chiffrée — détail du keystore de chacun dans
[`elasticsearch.md`](elasticsearch.md) et [`kibana.md`](kibana.md).

## Alternative plus légère : Grafana + Loki

Loki (de Grafana Labs) répond au même besoin (centraliser des logs) avec
une philosophie différente : indexer seulement les métadonnées
(étiquettes), pas le contenu complet de chaque ligne — bien moins
coûteux en ressources qu'Elasticsearch, qui indexe le texte intégral de
chaque document. Le compromis inverse : des recherches en texte libre
plus limitées. Pour un lab à une seule machine avec un volume de logs
modeste, les deux approches fonctionnent ; le choix ELK ici est motivé
par la valeur d'apprentissage (stack historique de référence de
l'industrie) plutôt que par une contrainte de ressources, voir
[`elk/README.md`](../../elk/README.md) pour la vérification réelle des
ressources disponibles avant ce choix.
