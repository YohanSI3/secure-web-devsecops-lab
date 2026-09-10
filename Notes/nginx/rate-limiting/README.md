# Rate limiting

## Contexte

Phase 2 du `ToDo.md` : « rate limiting ». Contrairement à
[fail2ban](../../fail2ban/README.md), qui réagit *a posteriori* à un motif
d'échecs répétés dans les logs, le rate limiting agit **au moment même de
la requête**, indépendamment de son succès ou de son échec — protection
contre le débit brut plutôt que contre un comportement malveillant
identifié.

Les choix concrets pour ce lab (zone, seuils, statut retourné) sont
documentés dans
[`nginx/README.md`](../../../nginx/README.md#rate-limiting) — cette note
couvre le fonctionnement général du module `limit_req` de Nginx.

## Le seau percé (leaky bucket)

Le module `ngx_http_limit_req_module` de Nginx implémente l'algorithme du
**seau percé** (*leaky bucket*) : chaque requête ajoute une unité dans un
« seau » associé à une clé (ici l'IP cliente) ; le seau se vide à un débit
constant (`rate=10r/s` = 10 unités par seconde) ; si une requête arrive
alors que le seau est plein, elle est retardée ou rejetée selon la
configuration.

Trois paramètres pilotent le comportement :

- **`rate`** — le débit soutenu autorisé une fois le seau stabilisé (ex.
  `10r/s`).
- **`burst`** — la capacité du seau au-delà du débit soutenu : combien de
  requêtes en excès sont tolérées d'un coup avant rejet (ex. `burst=20`
  autorise une rafale de 20 requêtes même si elles arrivent bien plus vite
  que 10/s, tant que le seau n'était pas déjà plein).
- **`nodelay`** — sans cette option, les requêtes qui rentrent dans le
  `burst` mais dépassent le `rate` soutenu sont **mises en attente**
  (retardées) pour lisser artificiellement le trafic au débit nominal ;
  avec `nodelay`, elles sont servies **immédiatement**, seul le dépassement
  du `burst` déclenche un rejet. Sans `nodelay`, un navigateur qui charge
  plusieurs ressources en parallèle subirait une latence artificielle
  même en usage parfaitement légitime.

## Pourquoi `$binary_remote_addr` plutôt que `$remote_addr`

`limit_req_zone` a besoin d'une **clé** pour isoler le compteur de chaque
client dans la zone mémoire partagée. `$remote_addr` est l'adresse IP sous
forme de texte (ex. `"192.168.1.1"`, jusqu'à 15 caractères en IPv4, 39 en
IPv6) ; `$binary_remote_addr` est la même adresse sous forme binaire
compacte (4 octets en IPv4, 16 en IPv6). Une zone mémoire de taille fixée
(`10m` ici) doit stocker un compteur par IP distincte observée : utiliser
la forme binaire réduit la taille de chaque entrée, donc augmente le
nombre de clients distincts trackables dans la même quantité de mémoire —
optimisation directement recommandée par la documentation Nginx, sans
compromis fonctionnel (la clé n'a besoin que d'identifier, pas d'être
lisible).

## Rejet : 429, pas un timeout ni une coupure silencieuse

Une requête qui dépasse `rate`+`burst` reçoit une réponse HTTP explicite
(configurable via `limit_req_status`, `429` dans ce lab plutôt que le
`503` par défaut de Nginx) — le client sait immédiatement qu'il a été
limité et pourquoi, plutôt que de subir un délai d'attente qui pourrait
être confondu avec un problème réseau ou un serveur en panne. Une vraie
API en production accompagnerait souvent ce `429` d'un header
`Retry-After` indiquant quand réessayer — raffinement possible mais non
ajouté ici (`limit_req` ne le fait pas nativement, demanderait un module
supplémentaire ou une logique applicative).

## Rate limiting vs fail2ban : deux protections complémentaires, pas redondantes

| | `limit_req` (rate limiting) | fail2ban |
|---|---|---|
| Déclenché par | le débit brut de requêtes, quel que soit leur statut | un motif d'échecs (ex. 404 répétés) sur une fenêtre de plusieurs minutes |
| Délai de réaction | immédiat, requête par requête | après coup, une fois le seuil d'échecs atteint |
| Sanction | rejet ponctuel de la requête en excès (429) | blocage de l'IP pendant une durée fixe (pare-feu) |
| Repérage | ne regarde jamais le contenu/résultat de la requête | analyse le contenu des logs déjà écrits |

Un scan lent (une requête invalide toutes les quelques secondes, sous le
seuil `maxretry`/`findtime` de fail2ban) peut passer inaperçu de fail2ban
mais resterait de toute façon sous le seuil de `limit_req` aussi — les
deux ont leurs angles morts respectifs, d'où l'intérêt de les combiner
plutôt que de compter sur un seul mécanisme.
