# Configuration Nginx versionnée + page statique

## Contexte

Suite de la Phase 1 du `ToDo.md` : servir une page statique simple via une
configuration Nginx versionnée dans le dépôt, plutôt que modifiée à la main
directement dans `/etc/nginx/`.

Cette note d'index résume la démarche. Le détail de chaque sujet technique
est réparti dans des fichiers séparés (trop de contenu pour un seul
fichier) :

- [`repo-vs-etc-nginx.md`](repo-vs-etc-nginx.md) — pourquoi et comment le
  fichier de config versionné est relié à `/etc/nginx/` (symlinks,
  `sites-available`/`sites-enabled`, `nginx -t`, reload).
- [`permissions-webroot.md`](permissions-webroot.md) — pourquoi le contenu
  statique n'est pas servi directement depuis le dépôt, et le modèle de
  permissions appliqué au webroot de déploiement.
- [`server-block-directives.md`](server-block-directives.md) — explication
  de chaque directive utilisée dans le server block.
- [`logs-et-privileges.md`](logs-et-privileges.md) — observation sur les
  logs par-site et le mécanisme d'héritage de descripteur de fichier entre
  master et workers.

## Ce qui a été fait

- Page statique source : [`app/static-site/index.html`](../../../app/static-site/index.html)
- Config nginx versionnée : [`nginx/sites-available/secure-web-lab.conf`](../../../nginx/sites-available/secure-web-lab.conf)
- Script de déploiement du contenu : [`scripts/deploy-static-site.sh`](../../../scripts/deploy-static-site.sh)
  → copie `app/static-site/` vers `/var/www/secure-web-lab/` avec des
  permissions restreintes.
- Script d'activation de la config : [`scripts/deploy-nginx-config.sh`](../../../scripts/deploy-nginx-config.sh)
  → symlink dans `/etc/nginx/sites-available/` puis `sites-enabled/`,
  désactivation du site `default`, `nginx -t`, `systemctl reload nginx`.

```bash
./scripts/deploy-static-site.sh
./scripts/deploy-nginx-config.sh
```

## Vérification

```bash
curl -sI -H "Host: secure-web-lab.local" http://localhost
# HTTP/1.1 200 OK

curl -sI http://localhost
# HTTP/1.1 200 OK (répond aussi sans Host header — voir repo-vs-etc-nginx.md)
```

Contenu de la page confirmé identique à `app/static-site/index.html`.
Logs dédiés créés : `/var/log/nginx/secure-web-lab.access.log` et
`secure-web-lab.error.log`.

## Prochaines étapes (Phase 1)

- séparation dev / staging / prod-lab
- TLS local ou lab
- headers de sécurité de base
- désactivation d'informations inutiles (ex : `server_tokens`)
