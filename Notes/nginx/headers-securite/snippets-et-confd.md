# Centralisation : `snippets/` et `conf.d/`

[`Notes/nginx/configuration/server-block-directives.md`](../configuration/server-block-directives.md)
avait documenté l'existence de `snippets/` et `conf.d/` dans l'arborescence
standard Debian sans encore les utiliser (le lab n'avait alors qu'un seul
site). Avec trois environnements et plusieurs headers communs, l'usage
réel de ces deux mécanismes devient concret.

## `nginx/snippets/security-headers.conf`

Un **snippet** est un fragment de configuration réutilisable, inclus
explicitement où besoin via `include`. Les six `add_header` communs aux
trois environnements sont regroupés dans un seul fichier, inclus dans
chaque server block HTTPS avec `include snippets/security-headers.conf;`.

Bénéfice concret : corriger ou ajouter un header de sécurité se fait
**une seule fois**, dans un seul fichier, plutôt que de dupliquer le
changement dans les trois fichiers `secure-web-lab-{dev,staging,prod}.conf`
— avec le risque, sinon, d'oublier un environnement ou d'introduire une
divergence non voulue entre eux. Un snippet est inclus explicitement (pas
automatiquement comme `conf.d/`) : il faut l'ajouter volontairement à
chaque server block qui en a besoin, ce qui convient bien ici puisque
seuls les server blocks HTTPS doivent inclure ces headers (pas les blocs
de redirection HTTP).

## `nginx/conf.d/security.conf`

Les fichiers de `conf.d/` sont chargés **automatiquement** par
`/etc/nginx/nginx.conf` (`include /etc/nginx/conf.d/*.conf;`, dans le
contexte `http`), sans avoir besoin d'un `include` explicite dans chaque
site. Utilisé ici pour `server_tokens off;` — un réglage global du serveur,
pas propre à un vhost, qui doit s'appliquer partout sans exception ni
possibilité d'oubli.

`ssl_protocols` avait initialement été placé ici aussi, avec le même
raisonnement ("doit s'appliquer partout"). Mauvais choix en pratique :
`nginx.conf` (stock, non versionné) déclare déjà `ssl_protocols` au même
niveau `http`, et cette directive **fusionne par addition** entre
plusieurs déclarations d'un même niveau plutôt que de se remplacer —
contrairement à la plupart des directives nginx. `ssl_protocols` a donc
été déplacé vers `nginx/snippets/tls-hardening.conf`, inclus explicitement
au niveau `server` de chaque vhost HTTPS, où l'héritage parent/enfant
remplace bien la valeur au lieu de fusionner. Détail complet dans
[`Notes/nginx/tls/protocoles-tls-heritage-et-fusion.md`](../tls/protocoles-tls-heritage-et-fusion.md).

## Pourquoi pas tout dans `conf.d/`, ou tout en `snippets/`

Distinction retenue : `conf.d/` pour ce qui doit s'appliquer partout sans
exception ni possibilité d'oubli, à condition que la directive utilisée
remplace (et non fusionne) une valeur déjà définie ailleurs au même
niveau ; `snippets/` pour ce qui doit être inclus consciemment à certains
endroits précis (chargement explicite), y compris quand ce choix est
motivé par un comportement de fusion à éviter plutôt que par une différence
de portée fonctionnelle. Les headers de sécurité restent en `snippets/`
en plus pour une seconde raison : ils ne concernent que les server blocks
HTTPS (un bloc de redirection HTTP n'a pas de corps de réponse à
protéger) — les mettre en `conf.d/` les aurait appliqués aussi aux blocs
de redirection, sans réel bénéfice.
