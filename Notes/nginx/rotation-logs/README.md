# Rotation de logs

## Contexte

Dernier point de la Phase 2 du `ToDo.md`. Sans rotation, les fichiers de
logs grossissent indéfiniment — problème de place disque à terme, mais
aussi de praticité (un fichier de plusieurs Go est difficile à consulter
ou à traiter). `logrotate` est l'outil standard Debian/Ubuntu pour gérer
ce cycle : renommer/compresser les anciens fichiers, en créer un nouveau,
purger au-delà d'une rétention définie — exécuté périodiquement par un
timer systemd (`logrotate.timer`), pas par Nginx lui-même.

Les choix concrets pour ce lab (périmètre des fichiers, permissions,
signal envoyé) sont documentés dans
[`nginx/README.md`](../../../nginx/README.md#rotation-de-logs) — cette
note couvre le fonctionnement général et pourquoi la rotation ne peut pas
se contenter de manipuler des fichiers sur le disque.

## Pourquoi pas un simple renommage de fichier

Déjà posé dans
[`Notes/nginx/configuration/logs-et-privileges.md`](../configuration/logs-et-privileges.md) :
le **master process** Nginx ouvre les fichiers de log une seule fois, au
démarrage ou au rechargement de la config, et les **workers** héritent de
ce descripteur de fichier déjà ouvert par `fork()` — ils n'ouvrent jamais
eux-mêmes le fichier avec leur propre identité. Un descripteur de fichier
Unix référence un **inode**, pas un **nom de chemin** : renommer ou
supprimer le fichier ne referme rien côté processus qui l'a déjà ouvert,
il continue d'écrire dans le même inode (désormais invisible depuis le
système de fichiers, mais toujours présent tant qu'au moins un
descripteur le référence) — l'espace disque n'est même pas libéré tant
que le worker n'a pas fermé ou ré-ouvert ce descripteur.

## Le signal `USR1` : rouvrir sans tout recharger

Pour qu'un renommage de fichier ait un effet réel, il faut que le
**master** rouvre explicitement les chemins de log configurés — c'est ce
que fait le signal `USR1` (`kill -USR1 <pid-master>`, équivalent à
`nginx -s reopen`) : le master ouvre à nouveau chaque fichier de log par
son chemin (créant un fichier neuf si l'ancien nom a été déplacé/supprimé
juste avant), obtient un nouveau descripteur, et le transmet aux workers.
Contrairement à un `reload` (`SIGHUP`), qui relit **toute** la
configuration et respawn des workers avec cette config, `USR1` ne touche
qu'aux fichiers de log — plus léger, sans risque de casser autre chose si
la configuration a par ailleurs une erreur en attente de correction.

Séquence correcte d'une rotation : renommer l'ancien fichier → envoyer
`USR1` (le master ouvre un nouveau fichier au nom d'origine, les workers
basculent dessus) → l'ancien fichier (toujours sur disque sous son
nouveau nom) peut être compressé/archivé sans risque, plus aucun
processus n'y écrit.

## Pourquoi deux configs logrotate distinctes plutôt qu'une

`logrotate` lit tous les fichiers de `/etc/logrotate.d/` et les traite
dans l'ordre alphabétique de leur nom. S'il rencontre un chemin de fichier
déjà couvert par une configuration traitée précédemment dans cet ordre,
il **ignore silencieusement** la seconde occurrence (visible uniquement
en mode debug/verbeux, `logrotate -dv`, jamais en exécution normale
silencieuse) — pas d'erreur, juste une config qui ne s'applique jamais
pour ce fichier. Avoir une configuration au glob large
(`/var/log/nginx/*.log`) traitée **avant** une configuration plus
spécifique (par ordre alphabétique du nom de fichier dans
`/etc/logrotate.d/`) revient donc à rendre la seconde inopérante sans
aucun signal d'alerte — la raison directe du choix documenté dans
[`nginx/README.md`](../../../nginx/README.md#rotation-de-logs) de
restreindre le glob de la configuration livrée par le paquet Ubuntu
plutôt que d'ajouter la nôtre à côté sans y toucher.
