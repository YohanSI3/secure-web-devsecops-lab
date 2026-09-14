# Backend — documentation technique

Choix d'implémentation concrets du backend applicatif (Phase 5 du
`ToDo.md`, IAM). Pour le fonctionnement général de Node.js/npm et de
PostgreSQL, voir [`Notes/nodejs/`](../../Notes/nodejs/README.md) et
[`Notes/postgresql/`](../../Notes/postgresql/README.md).

## État actuel

Scaffold minimal : [`src/index.js`](src/index.js) expose un unique
endpoint `GET /health`, qui vérifie aussi la connexion à PostgreSQL.
**Aucune route d'authentification n'existe encore** — l'identification/
authentification/permissions (le cœur de la Phase 5) arrive dans une
étape suivante, une fois ce socle vérifié en conditions réelles
(connexion DB, reverse proxy Nginx, healthcheck).

## Pourquoi Express

Choisi (voir mémoire de décision du projet) pour l'écosystème npm riche
en briques d'authentification déjà éprouvées (bcrypt, jsonwebtoken,
passport, express-session) et le bon support des outils déjà en place
dans ce dépôt (Semgrep couvre JavaScript nativement, Dependabot gère déjà
un écosystème `npm` sans configuration supplémentaire au-delà d'ajouter
l'écosystème dans [`.github/dependabot.yml`](../../.github/dependabot.yml) —
à faire une fois `package.json` stabilisé).

## `127.0.0.1` uniquement, jamais `0.0.0.0`

```js
app.listen(port, '127.0.0.1', ...)
```

Le backend n'écoute que sur l'interface loopback : même si `ufw` ou la
config Nginx étaient un jour mal réglés, le processus Node lui-même
refuse toute connexion qui n'arrive pas depuis la machine locale. Défense
en profondeur — la même logique que le firewall
([`firewall/README.md`](../../firewall/README.md)) et le rate limiting
Nginx, appliquée cette fois au niveau applicatif plutôt qu'au niveau
réseau.

## Connexion à la base : rôle dédié, pas superuser

[`scripts/setup-postgres-db.sh`](../../scripts/setup-postgres-db.sh) crée
un rôle `secure_web_lab_app`, propriétaire de sa seule base
`secure_web_lab` — même philosophie que l'utilisateur système dédié aux
workers Nginx
([`Notes/nginx/utilisateur-dedie/`](../../Notes/nginx/utilisateur-dedie/README.md)) :
un compte par service, sans droit au-delà de ce qui lui appartient
(pas de `CREATEDB`, `CREATEROLE`, ni `SUPERUSER`). Le mot de passe généré
est écrit dans `app/backend/.env` (jamais commité, voir
[`.gitignore`](.gitignore)) — jamais visible dans un historique de
commande au-delà de ce script.

`.env.example` documente les variables attendues sans valeurs réelles —
préparation directe de la Phase 4 (`.env.example` sans secrets réels,
déjà dans le `ToDo.md`).

**Bug réel au premier essai** : `GET /health` répondait
`{"status":"ok","db":"unreachable"}`. Cause : le mot de passe généré par
`openssl rand -base64 24` contenait un `/` — caractère réservé dans une
URI (`postgresql://user:PASSWORD@host/db`, où `/` sépare normalement
l'hôte du nom de la base). Sans percent-encoding, le parseur d'URL du
driver `pg` interprète ce `/` comme un séparateur structurel plutôt que
comme faisant partie du mot de passe, et tronque ce dernier au mauvais
endroit — échec d'authentification silencieux côté driver, remonté ici
comme `db: unreachable` sans détail. Corrigé en générant le mot de passe
en hexadécimal (`openssl rand -hex 24`, alphabet `[0-9a-f]` uniquement,
jamais ambigu dans une URI) plutôt qu'en base64.

## Nginx : `/api/` en reverse proxy

[`nginx/snippets/api-proxy.conf`](../../nginx/snippets/api-proxy.conf),
inclus pour l'instant uniquement dans le vhost `dev`
([`nginx/sites-available/secure-web-lab-dev.conf`](../../nginx/sites-available/secure-web-lab-dev.conf)) —
`staging`/`prod` suivront une fois ce socle vérifié. Le `location /api/`
inclut aussi `snippets/rate-limiting.conf` : le rate limiting protège
déjà l'API sans configuration supplémentaire (zone partagée avec le reste
du site, voir [`nginx/README.md`](../../nginx/README.md#rate-limiting)).

## Lancer en local

```bash
cd app/backend
npm install
npm start
```

Nécessite `DATABASE_URL` dans `.env` — généré par
[`scripts/setup-postgres-db.sh`](../../scripts/setup-postgres-db.sh), pas
à écrire à la main.

## Vérification

```bash
# Direct (bypass Nginx, confirme que le process tourne et parle à la DB)
curl -s http://127.0.0.1:3000/health

# À travers Nginx (confirme le reverse proxy)
curl -sk --resolve dev.secure-web-lab.local:8443:127.0.0.1 \
  https://dev.secure-web-lab.local:8443/api/health
```

Attendu dans les deux cas : `{"status":"ok","db":"ok"}`.

Exécuté (accès direct, après correctif du mot de passe ci-dessus) :

```text
$ curl -s http://127.0.0.1:3000/health
{"status":"ok","db":"ok"}
```

Backend confirmé fonctionnel et connecté à PostgreSQL. Passage à travers
Nginx (`/api/health`) à vérifier ensuite — nécessite d'abord de
redéployer la config `dev`
(`./scripts/deploy-nginx-config.sh dev`).
