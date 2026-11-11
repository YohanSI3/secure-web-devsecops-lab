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
