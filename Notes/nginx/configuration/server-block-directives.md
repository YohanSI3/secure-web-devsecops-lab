# Directives du server block utilisées

Référence : [`nginx/sites-available/secure-web-lab.conf`](../../../nginx/sites-available/secure-web-lab.conf)

## `server { ... }`

Un **server block** définit comment nginx doit traiter les requêtes qui
correspondent à certains critères d'adresse/port et de nom d'hôte. C'est
l'équivalent nginx d'un "virtual host" (vhost) : plusieurs server blocks
peuvent cohabiter pour servir des sites différents depuis la même instance
nginx.

## `listen 80;` / `listen [::]:80;`

Indique l'adresse et le port sur lesquels ce server block écoute.
`listen 80;` couvre les connexions IPv4 ; `listen [::]:80;` est nécessaire
séparément pour les connexions IPv6, les deux protocoles étant gérés
indépendamment par nginx. Sans la ligne IPv6, un client se connectant en
IPv6 ne serait pas nécessairement pris en charge par ce server block.

## `server_name secure-web-lab.local;`

Indique le(s) nom(s) d'hôte pour lesquels ce server block doit répondre,
comparé au header HTTP `Host` envoyé par le client. Permet à une même
instance nginx, sur la même adresse/port, de router différents domaines
vers des configurations différentes.

Nuance observée en pratique : `server_name` ne garantit **pas** à lui seul
qu'un site ne répondra qu'à son nom déclaré — voir la découverte du
comportement "default implicite" dans
[`repo-vs-etc-nginx.md`](repo-vs-etc-nginx.md).

## `root /var/www/secure-web-lab;`

Chemin de base du système de fichiers utilisé pour traduire l'URI d'une
requête en chemin de fichier réel. Une requête sur `/foo.html` est
recherchée à `/var/www/secure-web-lab/foo.html`.

## `index index.html;`

Fichier(s) essayé(s), dans l'ordre, quand une requête pointe vers un
répertoire plutôt qu'un fichier précis (ex. requête sur `/`).

## `location / { try_files $uri $uri/ =404; }`

Un bloc `location` définit un traitement spécifique pour les requêtes dont
l'URI correspond au motif indiqué (ici `/`, donc toutes les requêtes non
prises en charge par un `location` plus spécifique).

`try_files` essaie plusieurs cibles dans l'ordre jusqu'à en trouver une qui
existe :
1. `$uri` — le fichier exact demandé,
2. `$uri/` — le même chemin traité comme un répertoire (déclenche alors la
   directive `index`),
3. `=404` — si rien ne correspond, renvoie directement une erreur 404
   plutôt que de laisser nginx tenter un comportement par défaut moins
   prévisible (ex. lister le contenu d'un répertoire si `autoindex` était
   activé, ce qui n'est pas le cas ici — `autoindex` est désactivé par
   défaut dans nginx).

## `access_log` / `error_log`

Définissent des fichiers de logs **spécifiques à ce server block**, séparés
des logs globaux par défaut (`/var/log/nginx/access.log`,
`/var/log/nginx/error.log`, toujours actifs pour tout ce qui n'a pas de
directive dédiée). Utile dès qu'il y aura plusieurs sites : pouvoir isoler
le trafic et les erreurs de chacun plutôt que tout mélanger dans les mêmes
fichiers. Prépare aussi la Phase 5 (surveillance, corrélation par site).

Détail du comportement de ces fichiers (propriétaire, écriture par le
worker malgré des permissions a priori restrictives) documenté dans
[`logs-et-privileges.md`](logs-et-privileges.md).
