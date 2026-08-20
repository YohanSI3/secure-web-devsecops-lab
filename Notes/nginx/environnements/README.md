# Séparation dev / staging / prod-lab

## Contexte

Suite de la Phase 1 du `ToDo.md` : séparer les environnements plutôt que
de n'avoir qu'un seul site nginx. Sur un lab mono-machine (une seule
instance WSL2, pas plusieurs hôtes ni conteneurs à ce stade), les trois
environnements sont simulés par trois vhosts nginx distincts tournant en
parallèle sur la même machine, chacun sur son propre port.

Détail du raisonnement et des choix techniques dans des fichiers séparés :

- [`separation-strategy.md`](separation-strategy.md) — pourquoi des ports
  différents plutôt que uniquement des noms de domaine, et résolution du
  point de vigilance `default_server` laissé en suspens dans
  [`Notes/nginx/configuration/repo-vs-etc-nginx.md`](../configuration/repo-vs-etc-nginx.md).
- [`environment-specific-settings.md`](environment-specific-settings.md) —
  ce qui diffère réellement entre les trois configs (`autoindex`, header
  `X-Environment`, logs séparés) et pourquoi.

## Ce qui a été fait

- Renommage de la config existante en config "prod-lab" explicite :
  `nginx/sites-available/secure-web-lab.conf` →
  [`secure-web-lab-prod.conf`](../../../nginx/sites-available/secure-web-lab-prod.conf)
- Ajout de deux nouvelles configs :
  [`secure-web-lab-dev.conf`](../../../nginx/sites-available/secure-web-lab-dev.conf)
  (port 8080) et
  [`secure-web-lab-staging.conf`](../../../nginx/sites-available/secure-web-lab-staging.conf)
  (port 8081)
- Scripts de déploiement paramétrés par environnement :
  [`scripts/deploy-static-site.sh`](../../../scripts/deploy-static-site.sh)
  et
  [`scripts/deploy-nginx-config.sh`](../../../scripts/deploy-nginx-config.sh)
  prennent maintenant `dev`, `staging` ou `prod` en argument.
- Script de convenance :
  [`scripts/deploy-all-environments.sh`](../../../scripts/deploy-all-environments.sh)
  déploie les trois d'un coup.

```bash
./scripts/deploy-all-environments.sh
```

## Nettoyage nécessaire (migration depuis l'ancien setup)

L'ancien fichier `secure-web-lab.conf` a été renommé : les anciens
symlinks dans `/etc/nginx/` et l'ancien webroot pointent maintenant vers
une source qui n'existe plus sous son ancien nom. À exécuter avant le
déploiement des trois environnements :

```bash
sudo rm -f /etc/nginx/sites-enabled/secure-web-lab.conf
sudo rm -f /etc/nginx/sites-available/secure-web-lab.conf
sudo rm -rf /var/www/secure-web-lab
sudo rm -f /var/log/nginx/secure-web-lab.access.log /var/log/nginx/secure-web-lab.error.log
```

## Vérification

```bash
curl -sI http://localhost:8080 | grep -i x-environment   # X-Environment: dev
curl -sI http://localhost:8081 | grep -i x-environment   # X-Environment: staging
curl -sI http://localhost      | grep -i x-environment   # X-Environment: prod-lab
```

## Prochaines étapes (Phase 1)

- TLS local ou lab
- headers de sécurité de base
- désactivation d'informations inutiles (`server_tokens off;`)
