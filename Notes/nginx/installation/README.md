# Installation de Nginx

## Contexte

Première étape du projet (Phase 1 du `ToDo.md`) : mettre en place le serveur
web principal du lab. Nginx est installé depuis les dépôts officiels Ubuntu
(pas de PPA tiers ni de build depuis les sources) pour rester sur un chemin
de mises à jour de sécurité standard et simple à maintenir.

## Environnement

- OS : Ubuntu 24.04.4 LTS (noble), sous WSL2
- Kernel : `6.6.87.2-microsoft-standard-WSL2`
- init : systemd actif (PID 1), donc `systemctl` fonctionne normalement
  (ce n'est pas le cas de toutes les instances WSL2 par défaut — point à
  vérifier en cas de réplication de ce lab sur une autre machine)

## Ce qui a été fait

```bash
sudo apt update
sudo apt install -y nginx
```

Résultat :

```text
Setting up nginx (1.24.0-2ubuntu7.17) ...
 * Upgrading binary nginx                                                [ OK ]
```

Nginx est installé, activé et démarré automatiquement par le paquet Debian
(`nginx.service`, `enabled` + `active` juste après l'install — comportement
par défaut d'apt sur Ubuntu, pas une action manuelle).

## Vérification

```bash
nginx -v
# nginx version: nginx/1.24.0 (Ubuntu)

systemctl status nginx --no-pager
# Active: active (running)
# Loaded: /usr/lib/systemd/system/nginx.service; enabled; preset: enabled

curl -sI http://localhost
# HTTP/1.1 200 OK
# Server: nginx/1.24.0 (Ubuntu)
```

La page par défaut "Welcome to nginx!" est servie correctement sur
`http://localhost`.

## Ce qui a été appris

### Version installée : upstream vs paquet de distribution

`1.24.0-2ubuntu7.17` se décompose en deux parties :
- `1.24.0` — version **upstream**, publiée par le projet Nginx (nginx.org).
- `-2ubuntu7.17` — révision du **paquet Ubuntu**, maintenue par Canonical,
  qui peut inclure des correctifs de sécurité, de compatibilité ou de
  packaging sans changer la version upstream.

Distinction essentielle : la version "logicielle" (upstream) n'est pas la
version "packagée" (distribution). Une distribution garde souvent une
version upstream plus ancienne mais patchée, pour privilégier stabilité et
support plutôt que la dernière nouveauté — logique courante en environnement
serveur/production ("plus récent" n'égale pas "mieux pour la prod").
Conséquence pratique : ne pas supposer qu'une version packagée Ubuntu se
comporte exactement comme la documentation upstream la plus récente.

### Paquets et dépôts APT

Sous Debian/Ubuntu, un **paquet** est une unité installable via `apt`,
pouvant contenir binaires, fichiers de config, scripts, dépendances,
unités systemd, documentation. Une application est souvent scindée en
plusieurs paquets pour éviter d'installer des fichiers inutiles et
mutualiser les éléments communs : `nginx` (serveur) + `nginx-common`
(structure/config commune).

Chaque paquet provient d'un **dépôt** APT configuré sur la machine. Pour
Ubuntu 24.04 ("noble") :
- `noble-updates` — mises à jour stables publiées après la sortie,
- `noble-security` — correctifs de sécurité.

Le dépôt d'origine détermine la version disponible, la vitesse de réception
des correctifs, et la confiance accordée à la chaîne d'approvisionnement
logicielle. Les dépôts officiels réduisent le risque de paquet compromis et
offrent une traçabilité ; une source tierce non maîtrisée augmente le risque
supply chain (paquets compromis, versions non suivies, absence de
correctifs).

`apt-cache policy nginx` montre la version installée, la version
**candidate** (celle qu'APT choisirait à la prochaine installation/mise à
jour, selon les dépôts et priorités configurés), et les dépôts d'origine —
utile pour comprendre pourquoi une version a été retenue.

### Build "stable" packagé par la distribution

Un **build** est une version compilée et préparée pour être distribuée.
Ici, Canonical compile et intègre Nginx pour l'écosystème Ubuntu selon sa
propre logique de maintenance, en visant une version testée et cohérente
avec le reste du système — à distinguer d'un build "mainline" upstream pris
sans filtre. Comparaison utile pour plus tard : paquet Ubuntu vs nginx.org
vs image container vs alternatives (OpenResty, Caddy).

### Modèle de privilèges : utilisateur système, master/worker

Sous Linux, un service tourne sous une identité utilisateur (root,
`www-data`, `mysql`, ...) qui détermine ses droits de lecture, d'écriture et
d'exécution. **Principe de moindre privilège** : un service ne doit avoir
que les permissions nécessaires à sa fonction. Un processus compromis
tournant en root a un impact potentiellement total (lecture/modification du
système, persistence, mouvement latéral) ; réduire ses privilèges limite la
surface d'impact en cas de faille.

Nginx applique ce principe via son modèle **master/worker** :
- le **master process** démarre avec assez de privilèges (root) pour
  **binder** le port 80 (attacher le programme à un port réseau pour
  écouter les connexions) — sous Linux, les ports < 1024 sont privilégiés
  et nécessitent des droits élevés pour être ouverts ;
- les **worker processes**, qui traitent réellement le trafic HTTP exposé
  au réseau, tournent avec des droits réduits : `www-data`, défini par
  `user www-data;` dans `/etc/nginx/nginx.conf`.

C'est une mesure de confinement : une faille exploitée sur un worker
n'offre pas directement les privilèges root du master. Cette directive
`user` impacte aussi les droits nécessaires sur les fichiers statiques, les
certificats, les sockets, les logs et les répertoires temporaires — sujet à
creuser pour la Phase 2 (utilisateur dédié / permissions minimales).

### Arborescence de configuration (`/etc/nginx/`)

- `nginx.conf` — fichier principal, point d'entrée (utilisateur, nombre de
  workers, logs, inclusions, réglages HTTP généraux).
- `sites-available/` / `sites-enabled/` — convention **Debian/Ubuntu** (pas
  universelle à Nginx) : les configurations de **vhost** (virtual host —
  permet à un même serveur de servir plusieurs sites/domaines, ex.
  `site1.example.com`, `api.example.com`) sont stockées dans
  `sites-available/`, puis activées via un **symlink** (lien symbolique,
  pointeur vers un autre fichier géré par le système de fichiers) dans
  `sites-enabled/`. Sépare "config existante" de "config réellement
  chargée", limite les configs orphelines, documente ce qui est réellement
  exposé.
- `conf.d/` — fragments de config chargés automatiquement (paramètres
  globaux, configs annexes). Une inclusion mal maîtrisée peut exposer un
  site non prévu ou casser une politique TLS.
- `snippets/` — blocs réutilisables (ex. paramètres TLS communs, headers de
  sécurité) inclus dans plusieurs server blocks : corriger une politique à
  un seul endroit plutôt que de dupliquer dans chaque vhost.

Point général : cette organisation (`sites-available`/`sites-enabled`,
`conf.d`) vient du **packaging Debian**, pas d'un comportement universel de
Nginx — un build nginx.org, une image Alpine ou un container minimal
peuvent structurer différemment. D'où l'intérêt de distinguer le logiciel
lui-même, son packaging, et la convention de la distribution.

### Gestion du service : systemctl, start vs enable

`systemctl` est l'outil de gestion de `systemd` (démarrer, arrêter,
redémarrer, activer/désactiver au démarrage, consulter l'état).

Distinction clé :
- `start` — démarrer maintenant,
- `enable` — démarrer automatiquement aux prochains démarrages (boot).

Un service peut combiner ces états indépendamment (démarré sans être
activé, activé sans être démarré, les deux, ni l'un ni l'autre). Le paquet
Nginx active le service au boot par défaut — point à garder pour le
hardening : un service démarré automatiquement augmente la surface
d'exposition potentielle et peut redevenir actif après un reboot sans
contrôle explicite. Nuance : pour un service jugé critique, un démarrage
automatique volontaire et documenté reste légitime — la question centrale
est de savoir si le comportement est intentionnel et tracé, plutôt que
subi.

### Traçabilité, épinglage, reproductibilité, suivi de sécurité

- **Traçabilité de version** : capacité à répondre à "quelle version
  tourne, d'où vient-elle, quand a-t-elle changé". Sans épinglage, un
  `apt upgrade` global peut mettre Nginx à jour même sans commande dédiée,
  dès qu'une nouvelle version candidate est disponible — avec un risque de
  comportement modifié, module cassé, ou divergence entre machines.
- **Épinglage** (`apt-mark hold`) : bloque la mise à jour automatique d'un
  paquet pour éviter une dérive de version non voulue. Utile pour la
  reproductibilité et la stabilité, mais pas une solution universelle : un
  paquet bloqué trop longtemps peut rester exposé à une vulnérabilité déjà
  corrigée en amont. À traiter comme un outil de maîtrise du changement, pas
  comme un blocage permanent.
- **Reproductibilité** : capacité à recréer le même environnement de façon
  fiable (même OS, même version de paquet, même configuration, même
  comportement attendu) — central pour un projet destiné à être repris sur
  une autre machine ou par quelqu'un d'autre. Rejoint en DevSecOps
  l'Infrastructure as Code, le versioning, le pinning de versions, les
  images immuables, les pipelines contrôlés.
- **Suivi de sécurité** : surveillance des vulnérabilités, correctifs
  disponibles, versions installées, exposition réelle. Face à une CVE
  publiée sur Nginx, l'objectif est de pouvoir croiser rapidement version
  installée / source du paquet / disponibilité d'un correctif / calendrier
  de remédiation.

## Reproductibilité

Pour obtenir exactement le même setup, la version est pinnée plutôt que d'installer `nginx` sans contrainte de version.

Script : [`scripts/install-nginx.sh`](../../../scripts/install-nginx.sh)

```bash
./scripts/install-nginx.sh
```

Le script :
1. vérifie que l'OS est bien Ubuntu 24.04 (`noble`) — la version pinnée
   `1.24.0-2ubuntu7.17` est spécifique à ce dépôt et ne sera pas forcément
   disponible telle quelle sur une autre release Ubuntu/Debian ;
2. installe `nginx` et `nginx-common` à la version exacte
   `1.24.0-2ubuntu7.17` ;
3. exécute `apt-mark hold` sur ces deux paquets pour empêcher qu'un futur
   `apt upgrade`/`dist-upgrade` fasse dériver la version sans passer par une
   mise à jour volontaire et documentée ici.

**Limite connue** : cette approche fige la version mais dépend de la
disponibilité du paquet dans les dépôts Ubuntu (qui peuvent l'archiver avec
le temps). Si le projet a besoin de portabilité multi-OS plus poussée
(au-delà d'Ubuntu 24.04), migration vers Docker (prévu dans
`infra/docker/` selon l'architecture du `ToDo.md`) plutôt que de complexifier
ce script apt.

## Prochaines étapes (Phase 1)

- page web statique simple servie par nginx
- configuration nginx versionnée dans le dépôt (`nginx/` du repo, pas
  `/etc/nginx/` directement)
- séparation dev / staging / prod-lab
- voir `Notes/nginx/configuration/` (à venir)
