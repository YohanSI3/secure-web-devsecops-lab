# Création de l'utilisateur système et configuration de Nginx

## Utilisateur et groupe système

[`scripts/create-nginx-user.sh`](../../../scripts/create-nginx-user.sh) crée :

```bash
groupadd --system secure-web-lab
useradd --system --no-create-home --shell /usr/sbin/nologin \
  --gid secure-web-lab --comment "..." secure-web-lab
```

- **`--system`** — crée un compte dans la plage d'UID/GID réservée aux
  comptes de service (sous la plage des utilisateurs humains), qui
  n'apparaît pas dans les écrans de connexion et n'est pas destiné à un
  usage interactif. C'est la même catégorie de compte que `www-data`,
  `mysql` ou `syslog`.
- **`--no-create-home`** — aucun `/home/secure-web-lab` créé : un compte de
  service qui ne se connecte jamais n'a besoin d'aucun espace personnel.
  Moins de fichiers existants, c'est moins de surface à mal protéger.
- **`--shell /usr/sbin/nologin`** — même si quelqu'un obtenait les
  identifiants de ce compte (ou tentait un `su secure-web-lab`), aucun shell
  interactif ne serait lancé. `nologin` affiche un message et ferme
  immédiatement la session. Réduit l'utilité du compte pour un attaquant qui
  chercherait à l'utiliser comme point d'appui interactif plutôt que
  seulement comme identité de processus.
- **`--gid secure-web-lab`** — groupe primaire dédié plutôt que le groupe
  générique `nogroup` ou un groupe partagé : nécessaire pour pouvoir cibler
  précisément ce groupe dans les permissions du webroot (voir
  [`permissions-et-repertoires-temporaires.md`](permissions-et-repertoires-temporaires.md))
  sans donner accès à d'autres comptes qui utiliseraient le même groupe par
  ailleurs.
- Pas de mot de passe défini (`useradd` sans `-p` verrouille le compte par
  défaut sur Debian/Ubuntu — vérifiable avec `passwd -S secure-web-lab`,
  qui doit rapporter `L` pour *locked*) : aucune authentification par mot de
  passe possible pour ce compte, cohérent avec un compte qui ne doit jamais
  servir à une connexion.

Script idempotent : `getent group`/`getent passwd` vérifient l'existence
avant de créer, pour pouvoir être ré-exécuté sans erreur ni duplication.

## Pourquoi la directive `user` ne peut pas suivre le modèle habituel de ce dépôt

Le reste de la configuration Nginx versionnée dans ce dépôt (`nginx/conf.d/`,
`nginx/snippets/`, `nginx/sites-available/`) est relié par symlink dans
`/etc/nginx/` par
[`scripts/deploy-nginx-config.sh`](../../../scripts/deploy-nginx-config.sh),
en laissant `/etc/nginx/nginx.conf` lui-même comme fichier stock du paquet
Ubuntu, non versionné (déjà noté dans
[`nginx/conf.d/security.conf`](../../../nginx/conf.d/security.conf) à
propos de `ssl_protocols`).

La directive `user` fait exception à ce modèle pour une raison structurelle :
c'est une directive de **contexte racine** (« main context »), qui ne peut
apparaître qu'une seule fois, en dehors de tout bloc `http {}` ou
`server {}` — donc littéralement en dehors de tout ce que `conf.d/` ou
`snippets/` permettent d'inclure (ces répertoires sont inclus *depuis*
l'intérieur du bloc `http {}`). Elle ne peut être déclarée qu'à un seul
endroit : directement dans `nginx.conf`, avant tout bloc.

[`scripts/configure-nginx-user.sh`](../../../scripts/configure-nginx-user.sh)
traite donc ce fichier comme une exception délibérée et documentée (même
logique que l'épinglage de version de
[`scripts/install-nginx.sh`](../../../scripts/install-nginx.sh) : une
dérive contrôlée et tracée plutôt qu'une modification manuelle non
documentée) :

1. vérifie que la ligne `user secure-web-lab;` n'est pas déjà présente
   (idempotence) ;
2. sauvegarde `/etc/nginx/nginx.conf` avant modification
   (`nginx.conf.bak-<timestamp>`) — permet un retour arrière trivial si le
   `sed` produit un résultat inattendu sur une version de fichier stock
   différente de celle testée ;
3. remplace la ligne `user ...;` existante par `user secure-web-lab;` via
   `sed`, sans toucher au reste du fichier ;
4. `nginx -t` avant tout rechargement (cf.
   [`Notes/nginx/configuration/repo-vs-etc-nginx.md`](../configuration/repo-vs-etc-nginx.md#nginx--t-avant-reload)) ;
5. `systemctl reload nginx`.

## `reload` suffit-il pour un changement d'utilisateur ?

La directive `user` n'affecte que les workers, jamais le master (qui reste
lancé par systemd, en root, quelle que soit cette directive — c'est lui qui
a besoin de root pour *binder* les ports privilégiés, cf.
[`Notes/nginx/installation/README.md`](../installation/README.md#modèle-de-privilèges--utilisateur-système-masterworker)).
Un `reload` (SIGHUP) fait relire la config par le master et respawn des
workers neufs avec cette config — en théorie suffisant, sans le court arrêt
de service d'un `restart` complet.

**Confirmé à l'exécution** (voir
[`README.md`](README.md#ce-qui-a-été-fait-exécution-réelle)) :
`ps -eo user,pid,cmd | grep 'nginx: worker'` juste après le `reload` de
`configure-nginx-user.sh` a montré une coexistence transitoire d'anciens
workers `www-data` (en cours de terminaison de leurs requêtes) et de
nouveaux workers `secure-web-lab` (déjà actifs) — signature exacte d'un
reload réussi, pas besoin de `restart`.
