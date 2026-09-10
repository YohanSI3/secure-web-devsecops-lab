# Utilisateur dédié et permissions minimales

## Contexte

Suite de la Phase 2 du `ToDo.md` : « utilisateur dédié » et « permissions
minimales », traités ensemble car le second découle directement du premier
— changer l'identité des workers nginx implique de revoir tout ce qui leur
donne accès (webroot, répertoires temporaires).

Jusqu'ici, les workers nginx tournent sous `www-data`, l'utilisateur défini
par défaut par le paquet Debian/Ubuntu (voir
[`Notes/nginx/installation/README.md`](../installation/README.md#modèle-de-privilèges--utilisateur-système-masterworker)).
`www-data` est **partagé par convention** entre plusieurs services
potentiels d'une même machine (PHP-FPM, Apache, autres applis web). Sur une
machine qui n'héberge que ce lab, ce n'est pas un risque immédiat, mais ça
reste une mauvaise habitude par défaut : un utilisateur dédié à ce service
précis limite le rayon d'impact d'une compromission — un worker nginx
compromis n'hérite d'aucun accès pensé pour un autre service qui
utiliserait `www-data`, et réciproquement.

Détail réparti dans deux fichiers séparés :

- [`creation-et-configuration-utilisateur.md`](creation-et-configuration-utilisateur.md)
  — création de l'utilisateur/groupe système, et pourquoi la directive
  `user` de Nginx ne peut pas être gérée comme les autres réglages de ce
  dépôt (`conf.d/`, `snippets/`).
- [`permissions-et-repertoires-temporaires.md`](permissions-et-repertoires-temporaires.md)
  — revue complète de ce qui doit changer (webroot, `/var/lib/nginx/`) et de
  ce qui reste inchangé (certificats TLS, logs) suite au changement
  d'utilisateur, avec la justification pour chacun.

## Portée : un seul utilisateur pour les trois environnements

Les trois vhosts (dev/staging/prod-lab) sont servis par la **même** instance
Nginx (un seul master, un même jeu de workers, cf.
[`Notes/nginx/environnements/`](../environnements/README.md)) — la directive
`user` est globale à l'instance, pas par `server{}`. Un utilisateur dédié
*par environnement* n'apporterait donc aucune isolation réelle : les
workers d'un même processus peuvent de toute façon lire les trois webroots
simultanément, quel que soit le nombre d'utilisateurs système déclarés. Une
vraie séparation par environnement demanderait des instances Nginx
distinctes (hors périmètre actuel, cf. limite déjà notée dans
[`Notes/nginx/installation/README.md`](../installation/README.md) sur une
migration éventuelle vers Docker).

## Marche à suivre (ordre important)

```bash
./scripts/create-nginx-user.sh      # crée l'utilisateur/groupe système
./scripts/configure-nginx-user.sh   # bascule Nginx dessus, ajuste /var/lib/nginx, reload
./scripts/deploy-all-environments.sh # redéploie le webroot avec le nouveau groupe propriétaire
```

Cet ordre évite un creux d'accès : les workers basculent sur le nouvel
utilisateur (étape 2) avant que le webroot ne soit re-chown vers le nouveau
groupe (étape 3) — inverser les deux laisserait une fenêtre où les workers
(encore `www-data`) ne pourraient plus lire un webroot déjà passé au
nouveau groupe.

## Ce qui a été fait (exécution réelle)

Exécuté sur WSL2 Ubuntu 24.04 (noble) dédiée à ce lab — voir
[`Notes/nginx/installation/`](../installation/README.md) pour le contexte
de cette machine (créée spécifiquement après avoir découvert qu'une autre
distro WSL de la machine avait dérivé sur Ubuntu 26.04, incompatible avec
la version de Nginx pinnée par ce dépôt).

```bash
./scripts/create-nginx-user.sh
./scripts/setup-nginx-user.sh   # create + configure enchaînés
```

```text
Groupe 'secure-web-lab' créé.
Utilisateur 'secure-web-lab' créé.
--- Vérification ---
secure-web-lab:x:999:989:Worker processes Nginx (secure-web-devsecops-lab):/home/secure-web-lab:/usr/sbin/nologin
secure-web-lab:x:989:
uid=999(secure-web-lab) gid=989(secure-web-lab) groups=989(secure-web-lab)
Directive 'user' mise à jour dans /etc/nginx/nginx.conf (sauvegarde : /etc/nginx/nginx.conf.bak-20260910115252).
Propriétaire de /var/lib/nginx mis à jour.
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
--- Vérification ---
www-data    1127 nginx: worker process
[...]
secure-+    1325 nginx: worker process
[...] (12 workers de chaque, coexistence transitoire)
```

`groups=989(secure-web-lab)` confirme l'absence de tout groupe secondaire
(pas de `adm`, pas de `sudo`) — exactement le modèle visé dans
[`permissions-et-repertoires-temporaires.md`](permissions-et-repertoires-temporaires.md#ce-qui-na-délibérément-pas-été-fait).

Le `ps` juste après le `reload` montre les deux populations de workers en
même temps (`www-data` et `secure-web-lab`) : confirmation empirique que
`systemctl reload nginx` (SIGHUP) **suffit** à faire prendre effet un
changement de la directive `user`, sans `restart` — les anciens workers
`www-data` visibles ici terminaient leurs requêtes en cours avant de
s'arrêter, pendant que les nouveaux workers `secure-web-lab` prenaient le
relais. Détail dans
[`creation-et-configuration-utilisateur.md`](creation-et-configuration-utilisateur.md#reload-suffit-il-pour-un-changement-dutilisateur).

## Bug découvert en conditions réelles : `ls` de vérification sans `sudo`

```bash
./scripts/deploy-all-environments.sh
```

```text
=== dev ===
--- Déployé (dev) dans /var/www/secure-web-lab-dev ---
ls: cannot open directory '/var/www/secure-web-lab-dev': Permission denied
```

Le script s'est arrêté net ici (`set -euo pipefail` propage l'échec de
cette commande, la boucle `for env in dev staging prod` de
[`deploy-all-environments.sh`](../../../scripts/deploy-all-environments.sh)
ne va jamais jusqu'à `staging`/`prod`).

Cause : dans
[`deploy-static-site.sh`](../../../scripts/deploy-static-site.sh), toutes
les commandes qui écrivent dans `$DEST` sont préfixées `sudo` (elles
fonctionnent donc même invoquées par un utilisateur non-root), mais la
dernière ligne — `ls -la "$DEST"`, ajoutée uniquement pour l'affichage de
vérification — ne l'était pas. Tant que le webroot était `root:www-data`,
ça pouvait passer inaperçu selon que l'utilisateur humain exécutant le
script appartenait ou non à `www-data` (souvent le cas par héritage
d'anciennes installations). Une fois le webroot passé à `root:secure-web-lab`
— un groupe **neuf**, dont aucun humain n'est membre par construction (voir
[`creation-et-configuration-utilisateur.md`](creation-et-configuration-utilisateur.md))
— ce cas de figure devient systématique : plus aucun utilisateur interactif
ne peut lister ce répertoire sans élévation.

**Correctif** : `sudo ls -la "$DEST"`, cohérent avec le reste du script.
Bon exemple concret de pourquoi resserrer les permissions peut faire
remonter un bug latent ailleurs — la commande de *vérification* d'un
script avait, elle, toujours été un peu trop permissive dans ses propres
suppositions.

Contournement utilisé sur le moment, avant le correctif :
`sudo bash scripts/deploy-all-environments.sh` (tout le script en root,
rendant chaque `sudo` interne redondant mais sans effet néfaste).

## Vérification

```bash
ps -eo user,pid,cmd | grep '[n]ginx: worker process'
```

État stabilisé après le redéploiement complet (tous les workers sous
`secure-web-lab`, plus aucun `www-data`) et permissions du webroot
correctes par environnement (`root:secure-web-lab`, `750`/`640`,
confirmées par `sudo ls -la` dans la sortie de
`deploy-all-environments.sh` pour dev/staging/prod) et sites bien activés
(`sites-enabled/` contient les 3 vhosts).

## Suite

Phase 2 du `ToDo.md` terminée. Voir [`nginx/README.md`](../../../nginx/README.md),
[`firewall/README.md`](../../../firewall/README.md) et
[`fail2ban/README.md`](../../../fail2ban/README.md) pour le détail des
points traités ensuite.
