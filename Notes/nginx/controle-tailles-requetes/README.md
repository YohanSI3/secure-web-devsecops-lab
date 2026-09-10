# Contrôle des tailles de requêtes

## Contexte

Phase 2 du `ToDo.md` : « contrôle des tailles de requêtes ». Complète le
[rate limiting](../rate-limiting/README.md) : celui-ci borne le **débit**
de requêtes, cette étape borne la **taille** de chacune — deux dimensions
distinctes d'un même objectif, protéger la capacité du serveur (mémoire,
disque, temps de traitement) d'une requête ou d'un client donné.

Les choix concrets (valeurs retenues, pourquoi) sont documentés dans
[`nginx/README.md`](../../../nginx/README.md#contrôle-des-tailles-de-requêtes) —
cette note couvre le fonctionnement général des directives concernées.

## Deux surfaces distinctes : corps de requête vs en-têtes

Une requête HTTP a deux parties très différentes du point de vue de la
consommation de ressources serveur :

- **Le corps de requête** (*body*) — les données envoyées par le client
  après les en-têtes (contenu d'un formulaire, fichier uploadé, payload
  JSON d'une API). Peut légitimement être volumineux (upload de fichier) ;
  Nginx doit décider où le stocker temporairement pendant le traitement.
- **La ligne de requête et les en-têtes** — méthode, chemin, `Host`,
  cookies, `User-Agent`, etc. Censés rester courts ; une valeur
  anormalement longue ici (cookie de plusieurs kilo-octets, en-tête forgé)
  n'a aucune raison légitime d'être volumineuse, contrairement au corps.

Nginx traite ces deux surfaces avec des directives séparées, avec des
implications différentes en cas de dépassement.

## Corps de requête : `client_max_body_size` et `client_body_buffer_size`

- **`client_max_body_size`** — taille maximale absolue acceptée pour le
  corps d'une requête. Au-delà, Nginx répond **`413 Payload Too Large`**
  sans même chercher à traiter la requête plus loin. Défaut Nginx : `1m`.
- **`client_body_buffer_size`** — taille du tampon **mémoire** utilisé
  pour lire le corps de requête pendant sa réception. Un corps qui tient
  dans ce tampon reste entièrement en mémoire ; un corps plus grand (mais
  toujours sous `client_max_body_size`) déborde vers un fichier temporaire
  sur disque (voir
  [`Notes/nginx/utilisateur-dedie/permissions-et-repertoires-temporaires.md`](../utilisateur-dedie/permissions-et-repertoires-temporaires.md)
  pour où et sous quel utilisateur ces fichiers temporaires sont écrits).

Sans `client_max_body_size` fixée explicitement (ou avec une valeur trop
généreuse pour l'usage réel du site), un client peut forcer le serveur à
allouer de la mémoire et/ou de l'espace disque disproportionnés par
rapport à ce que le site est censé recevoir — une forme de déni de service
par épuisement de ressources, indépendante du débit de requêtes (donc non
couverte par le rate limiting).

## En-têtes : `client_header_buffer_size` et `large_client_header_buffers`

- **`client_header_buffer_size`** — taille du tampon utilisé pour la
  ligne de requête et les en-têtes dans le cas courant.
- **`large_client_header_buffers`** — nombre et taille des tampons
  utilisés quand un en-tête dépasse `client_header_buffer_size` (ex. un
  très gros cookie). Si même ces tampons plus grands ne suffisent pas,
  Nginx répond **`494 Request Header Too Large`**.

Une requête aux en-têtes anormalement volumineux peut viser à épuiser la
mémoire allouée par requête à grande échelle, ou exploiter un
comportement non prévu dans du code applicatif en amont qui lirait ces
en-têtes sans borne — pertinent même pour un site purement statique, la
limite s'applique avant que Nginx ne sache ce que la requête demande.

## Pourquoi ça complète le rate limiting sans faire doublon

Le [rate limiting](../rate-limiting/README.md) borne *combien* de
requêtes une IP peut envoyer par seconde, quelle que soit leur taille
individuelle. Le contrôle de taille borne *combien pèse* chaque requête
individuellement, quelle que soit la fréquence. Un client qui reste sous
le seuil de débit peut quand même tenter d'envoyer une requête unique
disproportionnée (upload massif, en-tête forgé) — angle mort du rate
limiting que le contrôle de taille couvre, et réciproquement une rafale de
requêtes minuscules mais très fréquentes est un angle mort du contrôle de
taille que le rate limiting couvre.
