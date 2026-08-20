# Webroot : pourquoi ne pas servir directement depuis le dépôt

## Le problème

Le dépôt Git vit sous `/home/pclk0713/Projets_Cyber_Perso/secure-web-devsecops-lab`.
Le dossier personnel `/home/pclk0713` a pour permissions `drwxr-x---` (750) :
seul son propriétaire (`pclk0713`) peut y entrer (bit `x`) et le lire.

Pour qu'un processus lise un fichier, il doit avoir le droit de **traverser**
(bit `x`) chaque répertoire parent jusqu'au fichier, en plus du droit de
**lire** (bit `r`) le fichier lui-même. Le worker nginx tourne sous
l'utilisateur `www-data`, qui n'appartient ni au propriétaire (`pclk0713`)
ni au groupe (`pclk0713`) de ce dossier personnel. Résultat : même avec un
`root /home/pclk0713/.../app/static-site;` dans la config, chaque requête
échouerait avec une erreur de permission (`13: Permission denied` dans les
logs nginx), le worker ne pouvant pas traverser `/home/pclk0713`.

Ce point diffère du fichier de config nginx lui-même (voir
[`repo-vs-etc-nginx.md`](repo-vs-etc-nginx.md)) : celui-ci est lu par le
**master process**, qui démarre en root et n'est jamais bloqué par ces
permissions. Le contenu statique, lui, est lu par les **workers** à chaque
requête HTTP, et reste donc pleinement soumis au modèle de permissions Unix
standard.

## La solution : déployer vers un webroot dédié

`scripts/deploy-static-site.sh` copie (via `rsync -a --delete`) le contenu
source de `app/static-site/` vers `/var/www/secure-web-lab/`, un chemin
hors du dossier personnel, dédié à l'usage web.

Conséquence à retenir : `/var/www/secure-web-lab/` est un **artefact
généré**, pas une source à éditer directement. Toute modification doit se
faire dans `app/static-site/` (source versionnée dans Git), puis être
redéployée via le script. `rsync --delete` garde en plus la destination
synchronisée avec la source : un fichier supprimé côté source disparaît
aussi du webroot au déploiement suivant, évitant l'accumulation de fichiers
obsolètes.

## Modèle de permissions appliqué

```
chown -R root:www-data /var/www/secure-web-lab
find ... -type d -exec chmod 750 {} \;   # répertoires : rwx r-x ---
find ... -type f -exec chmod 640 {} \;   # fichiers    : rw- r-- ---
```

Application directe du principe de moindre privilège déjà noté dans
[`Notes/nginx/installation/`](../installation/README.md) :

- **propriétaire `root`** — seul root peut modifier le contenu (via `sudo`
  dans le script de déploiement) ; le worker `www-data` ne peut pas écrire.
- **groupe `www-data`** — correspond au groupe d'exécution du worker nginx,
  qui obtient ainsi le droit de traverser les répertoires (`x`) et de lire
  les fichiers (`r`), strictement nécessaire pour servir le contenu.
- **aucun droit "other"** (`---`) — contrairement à un webroot classique
  souvent en `755`/`644` (lisible par n'importe quel utilisateur local du
  système), ce choix retire tout accès à quiconque n'est ni `root` ni
  membre de `www-data`. Pertinent sur une machine multi-utilisateurs ; sans
  effet ici en usage mono-utilisateur, mais bonne habitude à conserver par
  défaut plutôt qu'à ajouter après coup.

Les répertoires ont besoin du bit `x` (750) pour être traversés, mais pas
du bit `x` sur les fichiers (640) : un fichier HTML statique n'a pas besoin
d'être exécutable pour être lu et servi par nginx.
