# Revue des permissions après changement d'utilisateur

Changer l'identité des workers ne se limite pas à la directive `user` : tout
ce qui était accordé à `www-data` doit être réévalué pour le nouvel
utilisateur — ni oublié (le service casse), ni recopié aveuglément sans
vérifier que c'est encore nécessaire (accumulation de droits inutiles).
Revue poste par poste.

## Webroot — change (`www-data` → `secure-web-lab`)

Chaque fichier statique est ouvert en lecture par un **worker**, à chaque
requête (voir
[`Notes/nginx/configuration/permissions-webroot.md`](../configuration/permissions-webroot.md)).
Le worker tournant désormais sous `secure-web-lab`, le groupe propriétaire
du webroot doit suivre :

```bash
chown -R root:secure-web-lab /var/www/secure-web-lab-<env>
```

repris dans
[`scripts/deploy-static-site.sh`](../../../scripts/deploy-static-site.sh)
(variable `WEB_GROUP`). Le modèle reste identique par ailleurs — root
propriétaire, `750`/`640`, aucun accès *other* — seul le nom du groupe
change. Nécessite un redéploiement du contenu (`deploy-all-environments.sh`)
après le passage de `configure-nginx-user.sh` pour prendre effet ; les
fichiers déjà déployés avec l'ancien groupe ne changent pas tout seuls.

## Répertoires temporaires Nginx — change (`www-data` → `secure-web-lab`)

`/var/lib/nginx/{body,proxy,fastcgi,scgi,uwsgi}` (chemins exacts à confirmer
selon la version packagée réellement installée) stockent les corps de
requête ou réponses trop volumineux pour tenir en mémoire. Contrairement au
webroot (lecture seule) et aux logs (écrits via un descriptor hérité du
master, voir plus bas), ces fichiers sont **créés et écrits directement par
le worker qui traite la requête** — donc pleinement soumis à ses propres
permissions, sans raccourci possible. Un worker qui ne peut pas écrire dans
ces répertoires échoue silencieusement sur les requêtes qui débordent en
fichier temporaire (upload volumineux, réponse proxifiée de grande taille),
avec des erreurs qui n'apparaissent qu'à charge/volumétrie suffisante — pas
sur un test `curl` simple, d'où l'intérêt de fiabiliser ce point maintenant
plutôt que de le découvrir en Phase 2 sous rate limiting/contrôle de taille
de requêtes.

[`scripts/configure-nginx-user.sh`](../../../scripts/configure-nginx-user.sh)
applique donc `chown -R secure-web-lab:secure-web-lab /var/lib/nginx` dans
la foulée du changement de la directive `user`.

## Certificats TLS — inchangé

Aucun changement nécessaire sur
`/etc/nginx/ssl/<env>/{server.crt,server.key}` (`root:root`, `644`/`600`,
cf.
[`Notes/nginx/tls/deploiement-et-permissions.md`](../tls/deploiement-et-permissions.md)).
Le certificat et la clé privée sont lus une seule fois par le **master
process** (root) au chargement de la configuration TLS — jamais par un
worker, quel que soit son utilisateur. Le nouvel utilisateur dédié n'a donc
besoin d'aucun accès à `/etc/nginx/ssl/`, et ne devrait surtout pas en
recevoir : la clé privée reste strictement accessible à root seul. C'est
déjà le modèle le plus restrictif possible pour cet élément ; rien à
resserrer.

## Logs par-site — inchangé

Même raisonnement que les certificats, pour une raison différente cette
fois : `access_log`/`error_log` sont ouverts une seule fois par le master
(root) au chargement, et les workers écrivent ensuite via un **descripteur
de fichier hérité** du `fork()`, sans jamais ouvrir eux-mêmes le fichier
avec leurs propres droits (mécanisme détaillé dans
[`Notes/nginx/configuration/logs-et-privileges.md`](../configuration/logs-et-privileges.md)).
Le fichier reste `root:root`, `644`, et continuera de fonctionner à
l'identique quel que soit l'utilisateur des workers — aucune action requise.

## Tableau récapitulatif

| Élément | Propriétaire avant | Propriétaire après | Pourquoi |
|---|---|---|---|
| Webroot (`/var/www/secure-web-lab-<env>`) | `root:www-data` | `root:secure-web-lab` | lu directement par le worker à chaque requête |
| Temp Nginx (`/var/lib/nginx/*`) | `www-data:*` | `secure-web-lab:secure-web-lab` | écrit directement par le worker |
| Certificats/clé TLS (`/etc/nginx/ssl/<env>/`) | `root:root` | inchangé | lu par le master (root) uniquement |
| Logs par-site (`/var/log/nginx/*.log`) | `root:root` | inchangé | écrit via descripteur hérité du master |

## Ce qui n'a délibérément pas été fait

- Pas de groupes secondaires ajoutés à `secure-web-lab` (ni `adm`, ni
  `sudo`, ni aucun autre) : le compte n'a besoin d'aucun accès en dehors de
  son groupe primaire et des chemins listés ci-dessus.
- Pas de `sudoers` entry pour ce compte : les workers n'ont jamais besoin
  d'élever leurs privilèges, seul le master (déjà root) en a l'usage.
- Pas de tentative de faire tourner le **master** lui-même sous un
  utilisateur non-root : il en a besoin pour *binder* les ports privilégiés
  (80/443, cf.
  [`Notes/nginx/installation/README.md`](../installation/README.md)) et
  pour ouvrir logs/certificats avant que les permissions fines ne
  s'appliquent aux workers. C'est un choix d'architecture de Nginx
  lui-même (modèle master/worker), pas un point à durcir côté lab.
