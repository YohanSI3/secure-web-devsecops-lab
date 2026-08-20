# Source versionnée vs configuration vivante (`/etc/nginx/`)

Nginx charge sa configuration uniquement depuis `/etc/nginx/` (par
convention du paquet Debian/Ubuntu) au démarrage et au reload. Un fichier
de config qui vit seulement dans le dépôt Git n'a donc aucun effet tant
qu'il n'est pas relié à cet emplacement.

## Choix : symlink plutôt que copie

`scripts/deploy-nginx-config.sh` crée un lien symbolique :

```
/etc/nginx/sites-available/secure-web-lab.conf
    -> /home/.../secure-web-devsecops-lab/nginx/sites-available/secure-web-lab.conf
```

Un **symlink** garde une source unique de vérité (le fichier du dépôt) :
toute modification faite dans le dépôt est immédiatement effective au
prochain reload, sans étape de copie à répéter ni risque de divergence
entre "la config du dépôt" et "la config réellement appliquée". Une copie
demanderait de re-synchroniser manuellement à chaque changement, avec le
risque d'oublier et de travailler sur une version obsolète en croyant
tester la dernière.

Point de permission notable : le fichier de config vit sous le dossier
personnel (`/home/pclk0713`, `750`), inaccessible pour un utilisateur
normal du groupe `www-data`. Ce n'est pas un problème ici, car c'est le
**master process nginx**, qui démarre en root, qui lit ce fichier au
chargement de la config — et root n'est jamais bloqué par les bits de
permission Unix classiques. C'est une différence importante avec le
contenu statique (voir [`permissions-webroot.md`](permissions-webroot.md)),
lu par les **workers** (`www-data`) à chaque requête, eux bien soumis aux
permissions normales.

## Double indirection : `sites-available/` vs `sites-enabled/`

- `sites-available/` — toutes les configs de vhost connues, activées ou non.
- `sites-enabled/` — uniquement celles réellement chargées, via un symlink
  vers `sites-available/`.

Activer ou désactiver un site revient donc à ajouter/retirer un symlink
dans `sites-enabled/`, sans dupliquer ni supprimer le fichier de config
source. C'est cette mécanique qui a permis de désactiver le site `default`
sans le supprimer : il reste disponible dans `sites-available/default`,
simplement plus chargé.

## `nginx -t` avant `reload`

`nginx -t` vérifie la syntaxe et une partie de la sémantique de la
configuration (chemins référencés, blocs bien formés, directives valides)
**sans** l'appliquer. Exécuté avant tout rechargement, il évite de casser
un service en production avec une config invalide — un `reload` avec une
config cassée est refusé par nginx, qui continue de tourner avec l'ancienne
config déjà chargée en mémoire (le master ne remplace les workers qu'après
validation réussie).

## `systemctl reload` vs `restart`

- **`restart`** — arrête complètement le service puis le relance : brève
  coupure de service, toutes les connexions en cours sont interrompues.
- **`reload`** — envoie un signal au master process pour qu'il relise la
  configuration, démarre de nouveaux workers avec la nouvelle config, laisse
  les anciens workers terminer les requêtes en cours puis les arrête
  proprement. Aucune coupure de service pour les nouvelles connexions.

`reload` est utilisé ici (et à privilégier en général pour un changement de
config), `restart` restant nécessaire pour certains changements plus
profonds (ex. changement de version du binaire, de modules chargés).

## Découverte : comportement "default" implicite

En testant, la page répond aussi bien avec `Host: secure-web-lab.local` que
**sans** header `Host` explicite — alors qu'aucun `default_server` n'a été
déclaré dans `listen 80;`.

Explication : nginx choisit un serveur par défaut pour chaque couple
adresse/port (`80` ici) même sans directive `default_server` explicite —
il retient le **premier** server block déclaré pour ce couple
adresse/port. Une fois le site `default` désactivé, `secure-web-lab.conf`
est devenu le seul (donc le premier) server block sur le port 80, et sert
donc par défaut toute requête qui ne correspond à aucun `server_name`
connu.

Point de vigilance pour la suite : ce comportement implicite devient fragile
dès qu'un deuxième vhost sera ajouté (Phase 1 : séparation
dev/staging/prod-lab) — l'ordre de déclaration déciderait alors du site par
défaut, silencieusement. Il faudra alors déclarer `default_server`
explicitement sur le bon server block plutôt que de compter sur l'ordre.

> Suite donnée dans
> [`Notes/nginx/environnements/separation-strategy.md`](../environnements/separation-strategy.md) :
> `default_server` a été déclaré explicitement sur chaque environnement.
