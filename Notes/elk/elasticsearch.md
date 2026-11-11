# Elasticsearch

## Contexte

Le moteur qui stocke et indexe les logs centralisés de ce lab (voir
[`README.md`](README.md) pour la place d'Elasticsearch dans la chaîne
ELK). Les choix concrets pour ce lab (version, config, sécurité) sont
dans [`elk/README.md`](../../elk/README.md) ; cette note couvre le
fonctionnement général.

## Document, index, mapping : le vocabulaire de base

Elasticsearch organise les données en trois niveaux, à l'opposé du
modèle relationnel (base/table/ligne) :

- **Document** — une unité de données, un objet JSON (par exemple, une
  ligne de log Nginx déjà parsée en champs : IP, code de statut,
  horodatage). L'équivalent approximatif d'une ligne de table, en plus
  flexible : deux documents du même index n'ont pas forcément
  exactement les mêmes champs.
- **Index** — une collection de documents de même nature (par exemple,
  tous les logs Nginx d'une journée). L'équivalent approximatif d'une
  table, mais pensé pour la recherche plutôt que pour des jointures.
- **Mapping** — la définition du type de chaque champ d'un index
  (texte recherchable mot par mot, date, nombre, adresse IP comme type
  dédié plutôt que simple texte...). Déterminé automatiquement si on ne
  le précise pas (*dynamic mapping*), mais figé une fois un champ créé
  avec un type donné — changer le type d'un champ existant demande de
  recréer l'index, pas juste de modifier le mapping en place.

## L'index inversé : pourquoi une recherche est si rapide

Une base relationnelle classique, pour trouver "tous les documents qui
contiennent le mot X", devrait en général parcourir chaque ligne (sauf
index spécifique). Un moteur de recherche en texte intégral construit
l'inverse : un **index inversé**, une structure qui associe directement
chaque mot à la liste des documents qui le contiennent — chercher "tous
les documents avec X" devient une consultation directe de cette liste,
pas un parcours. C'est tout le "search" dans Elasticsearch : optimisé
pour ce schéma d'accès (recherche flexible par contenu), au prix d'une
structure moins adaptée à des mises à jour fréquentes d'un même document
ou à des relations complexes entre entités — d'où le choix fréquent de
l'utiliser en complément d'une base relationnelle, pas à sa place.

## Nœud, cluster, et le cas particulier d'une seule machine

Un **cluster** Elasticsearch est un ensemble de **nœuds** (process
Elasticsearch, en général un par machine) qui se répartissent les index
et répondent ensemble aux requêtes. Un cluster a besoin d'élire un nœud
**master** (coordination du cluster, pas des données elles-mêmes) — pour
ça, au démarrage d'un cluster tout neuf, Elasticsearch doit savoir
quels nœuds sont éligibles à ce rôle initial
(`cluster.initial_master_nodes`, une liste de **noms de nœuds**, pas
d'adresses). Sur un cluster à un seul nœud (le cas de ce lab), ce
mécanisme reste nécessaire : le nœud doit figurer dans sa propre liste
de bootstrap pour achever son élection, même seul. Piège direct qui en
découle, rencontré en pratique (voir
[`elk/README.md`](../../elk/README.md)) : si on renomme le nœud
(`node.name`) sans mettre à jour cette liste pour qu'elle corresponde,
le nœud ne peut jamais s'élire lui-même.

## Auto-configuration de sécurité : TLS et mot de passe superuser générés au premier démarrage

Depuis la version 8, installer le paquet Elasticsearch déclenche, au
tout premier démarrage, une **auto-configuration de sécurité** : des
certificats TLS auto-signés sont générés pour chiffrer le trafic HTTP et
inter-nœuds, et un mot de passe aléatoire est créé pour l'utilisateur
superuser `elastic` — affiché **une seule fois**, jamais récupérable en
clair après coup (seulement réinitialisable). Avant cette version, une
installation par défaut tournait souvent sans authentification ni
chiffrement activés, un vrai point faible longtemps reproché à la stack
ELK dans son usage le plus simple — corrigé en rendant la sécurité
active par défaut plutôt qu'une option à activer soi-même.

Ces réglages générés sont écrits directement dans
`elasticsearch.yml` (contrairement au mot de passe lui-même, stocké
chiffré dans le **keystore**, `elasticsearch.keystore`) — un
remplacement complet de ce fichier de configuration écraserait donc ces
réglages sans toucher au keystore, laissant une configuration
incohérente (vu en pratique, voir
[`elk/README.md`](../../elk/README.md) pour le bug réel correspondant).

## Dimensionnement du tas JVM : `Xms` = `Xmx`, jamais la mémoire totale

Elasticsearch tourne sur une JVM (Java), qui a son propre espace mémoire
géré séparément du reste du système (le **tas**, ou *heap*). Deux
réglages bornent sa taille : `Xms` (taille initiale) et `Xmx` (taille
maximale) — la pratique recommandée par Elastic est de les fixer à la
**même valeur**, pour éviter que la JVM ne redimensionne le tas en cours
de fonctionnement (une opération coûteuse). Ne jamais allouer la totalité
de la RAM disponible au tas : le système a aussi besoin de mémoire pour
mettre en cache les fichiers d'index sur disque (le *page cache* du
noyau), ce qui accélère en réalité les recherches autant que le tas
lui-même — Elastic recommande généralement de ne pas dépasser la moitié
de la RAM disponible pour le tas.
