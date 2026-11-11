# Logstash

## Contexte

La couche d'ingestion/transformation de la stack ELK, entre les fichiers
de logs bruts et Elasticsearch (voir [`README.md`](README.md) pour sa
place dans la chaîne). **Pas encore déployé dans ce lab** au moment de
l'écriture de cette note — contrairement à
[`elasticsearch.md`](elasticsearch.md) et [`kibana.md`](kibana.md), les
choix concrets ne sont donc pas encore dans
[`elk/README.md`](../../elk/README.md), ils y seront ajoutés une fois
cette étape faite. Note rédigée en préparation, pas après coup — reste
du cours général applicable indépendamment du moment où l'implémentation
suivra.

## Le pipeline : entrée, filtre, sortie

Logstash organise tout son travail en trois étapes successives,
configurées dans un seul fichier de pipeline :

- **input** — d'où viennent les données brutes (lire un fichier, écouter
  un port réseau, recevoir des événements d'un agent Beats comme
  Filebeat).
- **filter** — comment transformer chaque événement brut en document
  structuré : extraire des champs d'une ligne de texte, renommer,
  convertir un type, enrichir avec une donnée externe (résoudre une IP
  en pays, par exemple).
- **output** — où envoyer le résultat (typiquement Elasticsearch, mais
  Logstash peut aussi écrire vers un fichier, un autre système de
  messagerie, etc.).

Chaque événement traverse ce pipeline un par un ; plusieurs filtres
peuvent se chaîner dans l'ordre déclaré.

## Le filtre `grok` : extraire des champs d'une ligne de texte par motif

La plupart des logs (Nginx, fail2ban, PostgreSQL...) sont du texte libre
avec une structure implicite, pas du JSON déjà structuré. Le filtre
`grok` reconnaît cette structure via des motifs nommés réutilisables
(par exemple `%{IPORHOST:client_ip}` capture une adresse IP ou un nom
d'hôte dans le champ `client_ip`) — essentiellement des expressions
régulières prédéfinies et nommées, composables, plutôt que d'écrire une
regex complexe à la main pour chaque format de log. Une bibliothèque de
motifs standards existe pour les formats les plus courants (logs Apache,
syslog...), mais un format de log personnalisé (comme le format
`security_log` déjà utilisé pour Nginx dans ce lab, voir
[`Notes/nginx/journalisation/`](../nginx/journalisation/README.md))
demande généralement d'écrire son propre motif `grok`.

## Logstash vs Filebeat : pourquoi (et quand) combiner les deux

**Filebeat** (de la famille des *Beats*, agents légers développés par
Elastic) a un rôle plus étroit : surveiller des fichiers de logs et
expédier chaque nouvelle ligne vers une destination (Elasticsearch
directement, ou Logstash), sans transformation riche — une empreinte
mémoire/CPU bien plus faible que Logstash, pensée pour tourner sur de
nombreuses machines sans les charger. Logstash, lui, est la couche de
transformation plus complète (filtres `grok`, enrichissement,
agrégation d'événements multi-lignes) mais plus gourmande en
ressources.

Architecture courante qui en découle : **Filebeat installé sur chaque
machine qui produit des logs** (léger, juste lire et expédier),
**Logstash centralisé** qui reçoit de plusieurs Filebeat à la fois et
fait le travail de parsing lourd une seule fois, avant d'écrire dans
Elasticsearch. Sur un lab à une seule machine, cette séparation physique
n'apporte rien (tout tourne au même endroit) — mais le choix reste
pertinent pour isoler la configuration du parsing (dans Logstash) de la
simple collecte (Filebeat), ou pour utiliser directement Logstash en
entrée de fichier sans Filebeat du tout si la séparation ne sert à
rien dans ce contexte précis.
