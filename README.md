# secure-web-devsecops-lab
Hands-on lab for building, hardening, and securing modern web infrastructure with DevSecOps practices, secrets management, CI/CD, security testing ...

## Installation

```bash
./scripts/install-nginx.sh          # nginx, version pinnée
./scripts/setup-tls.sh              # CA locale + certificats TLS
./scripts/setup-nginx-user.sh       # utilisateur dédié + reconfiguration nginx
./scripts/deploy-all-environments.sh # contenu + config nginx, dev/staging/prod
```

Détail de chaque étape :
[`Notes/nginx/installation/`](Notes/nginx/installation/README.md),
[`Notes/nginx/tls/`](Notes/nginx/tls/README.md),
[`Notes/nginx/utilisateur-dedie/`](Notes/nginx/utilisateur-dedie/README.md),
[`Notes/nginx/environnements/`](Notes/nginx/environnements/README.md).

## Documentation

- [`ToDo.md`](ToDo.md) — plan général, objectifs, phases du projet.
- [`Notes/`](Notes/README.md) — journal d'apprentissage pas-à-pas (ce qui a
  été fait, comment, pourquoi).
