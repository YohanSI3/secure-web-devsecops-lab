# Kibana

## Contexte

La couche de visualisation/requête de la stack ELK, par-dessus
Elasticsearch (voir [`README.md`](README.md) pour sa place dans la
chaîne). Les choix concrets pour ce lab (config, enrôlement, clés de
chiffrement) sont dans [`elk/README.md`](../../elk/README.md) ; cette
note couvre le fonctionnement général.

## Un client d'Elasticsearch, pas un second entrepôt de données

Kibana ne stocke pas les logs lui-même — il interroge Elasticsearch
(requêtes de recherche, agrégations) et affiche le résultat sous forme
de tableaux de bord, graphiques, ou déclenche des actions (alertes). Les
seules données propres à Kibana sont ses **objets sauvegardés**
(configuration des tableaux de bord eux-mêmes, règles d'alerte, requêtes
enregistrées) — stockés, eux, dans un index Elasticsearch dédié géré par
Kibana, pas dans une base séparée. Conséquence pratique : sans
Elasticsearch disponible, Kibana n'a littéralement rien à afficher, y
compris sa propre interface de configuration.

## Jeton d'enrôlement : rejoindre le cluster sans partager le mot de passe superuser

Connecter Kibana à Elasticsearch ne passe plus (depuis la version 8) par
« donner à Kibana le mot de passe du compte superuser `elastic` » — à la
place, un **jeton d'enrôlement** à usage unique et à durée de vie courte
(quelques minutes) est généré côté Elasticsearch
(`elasticsearch-create-enrollment-token -s kibana`), puis consommé une
seule fois par Kibana (`kibana-setup --enrollment-token=...`). Le jeton
encode ce qu'il faut pour établir une connexion de confiance initiale
(empreinte du certificat TLS du cluster, entre autres) ; une fois
consommé, Kibana reçoit ses **propres** identifiants de service (pas le
mot de passe superuser), qu'il stocke chiffrés dans son propre keystore.
Même logique de fond que le jeton racine Vault ou l'AppRole
([`Notes/vault/README.md`](../vault/README.md)) : séparer « la clé
maîtresse qui ouvre tout » de « l'identité propre à chaque composant »,
pour qu'un composant compromis n'expose jamais que ses propres accès —
ici, un composant qui n'a jamais eu accès au mot de passe superuser ne
peut pas le divulguer, même compromis.

Pas besoin que ce jeton soit vu par un humain pour que l'enrôlement
fonctionne : il peut être généré puis consommé dans une seule commande
scriptée, sans jamais transiter par un terminal affiché ou une
conversation — contrairement au mot de passe `elastic` lui-même
(nécessairement affiché une fois, puisque c'est un humain qui doit s'en
servir pour se connecter à l'interface).

## Keystore de Kibana

Comme Elasticsearch, Kibana a son propre fichier **keystore**
(`kibana.keystore`) pour stocker des valeurs sensibles chiffrées
(notamment les identifiants de service obtenus via l'enrôlement) séparé
du fichier de configuration principal (`kibana.yml`), qui reste en
clair. Voir [`README.md`](README.md#keystore-vs-fichier-de-config-en-clair--un-principe-partagé-par-e-et-k)
pour le principe partagé avec Elasticsearch.

## Clés de chiffrement internes : pas la même chose que l'authentification vers Elasticsearch

Au-delà de sa connexion à Elasticsearch, Kibana a besoin de ses
**propres** clés de chiffrement pour des fonctionnalités qui n'ont rien
à voir avec l'authentification externe :

- `xpack.security.encryptionKey` — signe les cookies de session des
  utilisateurs Kibana (pas ceux d'Elasticsearch).
- `xpack.encryptedSavedObjects.encryptionKey` — chiffre les objets
  sauvegardés sensibles (identifiants stockés dans la config d'un
  connecteur d'alerte, par exemple) avant de les écrire dans
  l'index Elasticsearch qui les contient.

Sans ces clés configurées explicitement, Kibana en génère une aléatoire
à **chaque démarrage** : toutes les sessions utilisateur deviennent
invalides au redémarrage suivant, et plus grave, certaines API
(Alerting, Actions) se désactivent carrément plutôt que de tourner avec
une clé qui pourrait changer sous leurs pieds à tout moment — une perte
de fonctionnalité qui ne produit qu'un avertissement dans les logs, pas
une erreur bloquante visible dans l'interface, facile à manquer si on ne
lit pas les logs de démarrage avec attention (vécu en pratique, voir
[`elk/README.md`](../../elk/README.md)).

## Discover, Lens, tableaux de bord : trois couches, pas trois synonymes

Trois façons différentes d'exploiter les mêmes données Elasticsearch
dans Kibana, qu'on peut confondre au premier abord parce qu'elles
partagent la même barre de requête KQL et la même vue de données :

- **Discover** — exploration de documents **bruts**, un par un, triés
  (par défaut par horodatage décroissant). Pensé pour « que contiennent
  réellement mes données, ligne par ligne » : filtrer, ajouter des
  colonnes, trier — jamais d'agrégation. Une recherche Discover peut être
  **enregistrée** (une requête + un jeu de colonnes + un tri, nommés et
  réutilisables), y compris comme panneau de tableau de bord.
- **Lens** — l'éditeur de **visualisations**, construit autour
  d'**agrégations** : histogrammes temporels (compter des documents par
  tranche de temps), tableaux de valeurs les plus fréquentes (*top
  values*, un `terms` Elasticsearch), métriques simples. Un champ glissé
  en “ligne” d'un tableau Lens n'est jamais traité comme une liste brute
  à afficher telle quelle — toujours réinterprété comme un axe
  d'agrégation (un champ de date, par exemple, devient un histogramme à
  intervalle fixe, pas un simple tri chronologique de documents).
- **Dashboard** — un canevas qui assemble des panneaux des deux types
  précédents (visualisations Lens *et* recherches Discover enregistrées),
  chacun gardant sa propre configuration mais partageant la plage
  temporelle et les filtres globaux du tableau de bord.

Confusion fréquente, rencontrée en pratique dans ce lab (voir
[`elk/README.md`](../../elk/README.md) pour l'exemple réel) : vouloir
afficher « la liste des derniers événements X » en tableau **Lens**, en y
glissant un champ de date comme s'il s'agissait d'un simple tri. Lens
produit alors un histogramme croisé avec les autres champs choisis — un
tableau énorme, en grande partie vide, pas une liste d'événements.
L'outil fait pour « lister des documents bruts triés » est Discover (et
sa recherche enregistrée pour l'intégrer à un tableau de bord), pas Lens
— le bon réflexe est de partir de la question (« je veux voir chaque
événement » vs « je veux compter/grouper des événements ») pour choisir
l'outil, plutôt que de forcer un seul outil à tout faire.

## Alerting : règles, connecteurs, et fréquence d'action — trois notions séparées

Une **règle** (*rule*) Kibana Alerting combine trois choses distinctes :

- **une condition**, définie par un *type de règle* (par exemple
  « requête Elasticsearch dépasse un seuil de documents sur une fenêtre
  glissante ») — chaque type de règle a sa propre logique de
  vérification et fournit son propre jeu de variables de gabarit
  (`context.*`) utilisables dans les actions ;
- **une planification** (*schedule*) — à quelle fréquence la condition
  est vérifiée (indépendant de la fréquence à laquelle une action se
  déclenche réellement, voir plus bas) ;
- **une ou plusieurs actions**, déclenchées quand la condition est
  remplie, chacune pointant vers un **connecteur**.

Un **connecteur** (*connector*) est une destination de notification
générique et réutilisable entre règles — email, webhook, Slack,
PagerDuty, ou plus simplement écrire un document dans un index
Elasticsearch ou une ligne dans le propre journal du serveur Kibana. Le
type de règle ne détermine jamais le connecteur utilisable : n'importe
quelle règle peut pointer vers n'importe quel connecteur disponible.
Certains connecteurs sont réservés à des paliers de licence payants
(voir [`Notes/devsecops/paysage-outillage.md`](../devsecops/paysage-outillage.md)
pour un cas réel rencontré dans ce lab : le connecteur Email).

La **fréquence d'action** (*action frequency*) régit, séparément de la
planification de la règle, à quel moment une action se redéclenche
réellement pendant qu'une même alerte reste active — notamment
« à chaque changement de statut » (*on status change*, l'action ne se
redéclenche pas à chaque vérification périodique tant que la même alerte
reste active, seulement au passage **inactif → actif** et **actif →
récupéré**) par opposition à une notification répétée à chaque
vérification. Une alerte individuelle (une instance précise de la
condition remplie, par exemple « cette IP précise ») suit un cycle de vie
à trois états : **inactive** (condition non remplie), **active**
(condition remplie, au moins une vérification), **récupérée**
(*recovered* — condition de nouveau non remplie après avoir été active).
Distinguer ces trois notions (condition, destination, cadence de
notification) évite de confondre « la règle vérifie toutes les
minutes » (planification) avec « l'action se redéclenche toutes les
minutes » (pas le cas par défaut avec « on status change »).
