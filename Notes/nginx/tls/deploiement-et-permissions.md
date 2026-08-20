# Déploiement des certificats et modèle de permissions

## Emplacement

`scripts/deploy-tls-cert.sh` copie `server.crt`/`server.key` depuis
`.tls/<env>/` (généré, gitignoré) vers `/etc/nginx/ssl/<env>/` — une copie,
pas un symlink, contrairement à la config nginx elle-même (voir
[`Notes/nginx/configuration/repo-vs-etc-nginx.md`](../configuration/repo-vs-etc-nginx.md)).

Distinction volontaire : un fichier de config nginx n'est pas un secret —
le symlinker directement depuis le dépôt garde une source unique de vérité
sans risque particulier. Une clé privée TLS **est** un secret : la copier
explicitement vers un emplacement système dédié évite qu'elle continue de
"dépendre" d'un chemin de dépôt qui pourrait être déplacé, nettoyé, ou
(erreur humaine) un jour rendu public par inadvertance. Une fois déployée,
la clé vit dans `/etc/nginx/ssl/`, indépendamment du sort de `.tls/`.

## Permissions : plus strictes que le webroot

```bash
chown root:root server.crt server.key
chmod 644 server.crt   # public, pas un secret
chmod 600 server.key   # secret, accès root uniquement
```

À comparer avec le modèle appliqué au webroot statique
([`Notes/nginx/configuration/permissions-webroot.md`](../configuration/permissions-webroot.md)) :
`root:www-data`, `750`/`640`, où le groupe `www-data` a besoin d'un accès
en lecture parce que les **workers** lisent directement le contenu servi à
chaque requête.

La clé privée TLS, elle, n'est jamais lue par les workers : comme le
fichier de configuration nginx lui-même, elle est lue une seule fois par le
**master process** (root) au chargement ou au reload, pour établir le
contexte SSL. Les workers utilisent ensuite ce contexte déjà chargé en
mémoire sans avoir besoin d'accéder au fichier sur disque. Aucune raison,
donc, d'accorder le moindre accès à `www-data` sur ce fichier — `600
root:root` est à la fois suffisant et strictement plus restrictif que ce
qu'exigerait le contenu statique. Bon exemple concret du principe de
moindre privilège appliqué différemment selon qui a réellement besoin de
lire quoi, et à quel moment du cycle de vie du processus.

## Certificat public (`server.crt`) : `644`, pas de restriction particulière

Le certificat en lui-même (partie publique) est justement conçu pour être
communiqué à n'importe quel client qui se connecte — il transite déjà en
clair pendant le handshake TLS. Le protéger sur le disque au-delà d'un
`644` standard n'apporterait rien : seule la clé privée associée doit
rester confidentielle.
