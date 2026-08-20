# Logs par-site : écriture malgré des permissions restrictives

## Observation

```bash
stat -c '%A %U:%G %n' /var/log/nginx/secure-web-lab.access.log
# -rw-r--r-- root:root /var/log/nginx/secure-web-lab.access.log
```

Ce fichier appartient à `root:root`, avec pour "other" (donc pour
`www-data`, qui n'est ni le propriétaire ni membre du groupe `root`)
uniquement un droit de **lecture** (`r--`), aucun droit d'écriture. Pourtant,
les requêtes HTTP traitées par les workers (exécutés sous `www-data`) sont
bien enregistrées dans ce fichier — donc une écriture a bien eu lieu depuis
un processus `www-data`.

À comparer avec les logs globaux par défaut du paquet :

```bash
stat -c '%A %U:%G %n' /var/log/nginx/access.log
# -rw-r----- www-data:adm /var/log/nginx/access.log
```

Ceux-ci appartiennent directement à `www-data`, avec un droit d'écriture
explicite pour le groupe `adm`. Deux fichiers de logs, deux modèles de
permissions différents, mais une écriture qui fonctionne dans les deux cas.

## Explication : héritage de descripteur de fichier

Le **master process** nginx démarre et tourne en `root`. Au chargement (ou
rechargement) de la configuration, c'est lui qui ouvre (`open()`) tous les
fichiers référencés par les directives `access_log`/`error_log` — avec les
privilèges root, donc sans être bloqué par les permissions du fichier
(`secure-web-lab.access.log` a été créé directement par le master, d'où sa
propriété `root:root`).

Les **worker processes** sont ensuite créés par `fork()` depuis le master.
Un `fork()` duplique le processus, y compris ses **descripteurs de fichier
déjà ouverts** — le worker hérite donc du descripteur du fichier de log,
déjà ouvert en écriture par le master avant le fork. Le worker peut alors
écrire dedans via ce descripteur hérité, **sans avoir besoin d'ouvrir le
fichier lui-même** avec ses propres droits (`www-data`). Le contrôle de
permission Unix (`open()`) n'intervient qu'à l'ouverture du fichier, pas à
chaque écriture sur un descripteur déjà ouvert.

C'est une distinction importante entre :
- **le contenu statique servi** (`root /var/www/secure-web-lab;`) — chaque
  fichier est ouvert en lecture par le worker à chaque requête, donc
  pleinement soumis à ses propres permissions (voir
  [`permissions-webroot.md`](permissions-webroot.md)) ;
- **les fichiers de log** — ouverts une seule fois par le master (root) au
  chargement, puis écrits via un descripteur hérité par les workers, donc
  indépendants des permissions propres à `www-data` sur ce fichier précis.

## Implication pratique : rotation de logs

Cette mécanique explique pourquoi la rotation de logs (renommer/supprimer
l'ancien fichier, en créer un nouveau au même chemin — typiquement via
`logrotate`) ne peut pas se contenter de manipuler les fichiers sur le
disque : les workers continueraient d'écrire dans l'ancien fichier (déjà
supprimé du système de fichiers mais toujours ouvert via leur descripteur
hérité), tant qu'ils n'ont pas rouvert le nouveau chemin.

C'est pour cette raison que la rotation de logs nginx passe par un signal
envoyé au **master** (`nginx -s reopen`, ou `kill -USR1 <pid-master>`), qui
rouvre alors les fichiers de log configurés et transmet les nouveaux
descripteurs aux workers — plutôt que de compter sur les workers pour s'en
apercevoir eux-mêmes. Point à retrouver en Phase 2 (rotation de logs).
