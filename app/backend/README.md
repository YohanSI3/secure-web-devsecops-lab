# Backend — documentation technique

Choix d'implémentation concrets du backend applicatif (Phase 5 du
`ToDo.md`, IAM). Pour le fonctionnement général de Node.js/npm et de
PostgreSQL, voir [`Notes/nodejs/`](../../Notes/nodejs/README.md) et
[`Notes/postgresql/`](../../Notes/postgresql/README.md).

## État actuel

Socle (connexion DB, reverse proxy Nginx, healthcheck) vérifié en
conditions réelles — voir la section Vérification plus bas. Routes
d'authentification maintenant implémentées :
[`src/routes/auth.js`](src/routes/auth.js) (`POST /auth/register`,
`POST /auth/login`, `POST /auth/logout`, `GET /auth/me`) et
[`src/routes/admin.js`](src/routes/admin.js) (`GET /admin/ping`, route de
démonstration RBAC).

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

## Authentification (`src/routes/auth.js`)

### Mots de passe : bcrypt, coût 12, longueur minimale seule

`bcrypt.hash(password, 12)` — le coût 12 (2^12 itérations) est un défaut
moderne raisonnable, ajustable si le matériel change (voir
[`Notes/iam/mots-de-passe.md`](../../Notes/iam/mots-de-passe.md) pour
comment choisir ce nombre). Aucune règle de composition imposée
(majuscule/chiffre/symbole obligatoires) au-delà d'une longueur minimale
(10 caractères) : les recommandations actuelles (NIST SP 800-63B)
déconseillent ces règles, qui poussent surtout vers des mots de passe
prévisibles (`Password1!`) sans gain de sécurité réel — détail dans la
note ci-dessus.

### Sessions côté serveur (PostgreSQL), pas de JWT

`express-session` + `connect-pg-simple` : l'état de session vit en base
(table `session`, créée automatiquement par le module), le cookie ne
porte qu'un identifiant signé. Choisi plutôt qu'un JWT auto-porteur pour
cette phase : une session peut être **révoquée immédiatement** (supprimer
la ligne en base déconnecte l'utilisateur sur-le-champ), alors qu'un JWT
classique reste valide jusqu'à expiration même si on "annule" la
connexion côté client — nuance importante pour un cas d'usage IAM (ex.
désactiver un compte compromis doit couper l'accès immédiatement). Détail
comparatif dans
[`Notes/iam/sessions-vs-jwt.md`](../../Notes/iam/sessions-vs-jwt.md).

Réglages du cookie (`src/index.js`) :

- `httpOnly: true` — inaccessible en JavaScript côté client, ne peut pas
  être exfiltré par une XSS qui lirait `document.cookie`.
- `secure: true` — jamais envoyé en clair ; nécessite `trust proxy` (voir
  plus bas) pour qu'Express sache que la connexion **client** est bien en
  HTTPS, même si la connexion Nginx → Node ne l'est pas.
- `sameSite: 'lax'` — le cookie ne part pas sur une requête cross-site
  déclenchée par un autre site (protection CSRF partielle ; `lax` plutôt
  que `strict` pour ne pas casser une navigation normale depuis un lien
  externe).

### `trust proxy` : pourquoi c'est nécessaire ici précisément

```js
app.set('trust proxy', 1);
```

Le TLS se termine chez Nginx ; la connexion Nginx → Node
(`nginx/snippets/api-proxy.conf`) est en clair sur `127.0.0.1`. Sans ce
réglage, Express se fierait uniquement à cette connexion locale pour
juger si la requête est "sécurisée" — donc **jamais**, et le cookie
`secure: true` ne serait jamais transmis au navigateur, cassant
silencieusement toute session. `trust proxy` fait lire à Express le
header `X-Forwarded-Proto` (déjà positionné par
[`nginx/snippets/api-proxy.conf`](../../nginx/snippets/api-proxy.conf))
pour connaître le protocole réellement utilisé par le client — meilleure
alternative de tester ça sans avoir un vrai flux à travers Nginx.

### Résistance à l'énumération de comptes

Même réponse (`401 {"error":"invalid_credentials"}`) que l'email
n'existe pas, que le mot de passe soit faux, ou que le compte soit
verrouillé — jamais de distinction visible pour l'appelant. Le cas "email
inexistant" hache quand même le mot de passe soumis
(`bcrypt.hash(password, 12)`, résultat jeté) pour que le temps de réponse
reste comparable à une vraie comparaison — sans ça, une réponse plus
rapide pour un email absent permettrait de deviner quels comptes
existent par simple mesure de latence.

### Verrouillage de compte après échecs répétés

5 échecs consécutifs → verrouillage 15 minutes (`users.failed_attempts`,
`users.locked_until`). Par **compte**, pas par IP : un attaquant qui
changerait d'adresse à chaque tentative ne contourne pas ce verrouillage
(contrairement au rate limiting Nginx, par IP — les deux sont
complémentaires, voir
[`nginx/conf.d/rate-limiting.conf`](../../nginx/conf.d/rate-limiting.conf)
pour la zone `login` dédiée à `/api/auth/login`, plus stricte que le
reste du site).

### RBAC minimal : colonne `role`, pas encore de table de permissions

`users.role` (`'user'` ou `'admin'`, contrainte `CHECK`) plutôt qu'un
modèle many-to-many rôles/permissions — suffisant pour démontrer le
principe (voir [`src/middleware/auth.js`](src/middleware/auth.js),
`requireRole('admin')`, et
[`src/routes/admin.js`](src/routes/admin.js) comme exemple de route
protégée). Un vrai modèle RBAC extensible (plusieurs permissions par
rôle, rôles personnalisés) serait l'évolution naturelle si le besoin
grandit — non fait ici pour rester lisible tant qu'il n'y a que deux
niveaux d'accès. Aucune route API ne permet à un compte de s'auto-
promouvoir : [`scripts/promote-admin.sh`](../../scripts/promote-admin.sh)
agit directement en base, geste réservé à un accès opérateur.

### Fixation de session

`req.session.regenerate()` est appelé **avant** d'écrire `userId`/`role`
en session, à l'inscription comme à la connexion — un identifiant de
session émis avant authentification ne devient donc jamais valide après
authentification. Sans ça, un attaquant capable d'imposer un ID de
session à sa victime avant qu'elle ne se connecte (fixation de session)
récupérerait une session authentifiée valide une fois la victime
connectée.

### Audit (`src/audit.js`)

Chaque tentative de connexion (succès, échec, échec par verrouillage,
email inconnu), inscription et déconnexion est journalisée dans
`audit_log` (voir [`db/schema.sql`](db/schema.sql)) — `user_id` peut être
`null` (email inconnu à la connexion) sans jamais bloquer l'écriture de
la trace elle-même.

## Nginx : `/api/` en reverse proxy

[`nginx/snippets/api-proxy.conf`](../../nginx/snippets/api-proxy.conf),
inclus pour l'instant uniquement dans le vhost `dev`
([`nginx/sites-available/secure-web-lab-dev.conf`](../../nginx/sites-available/secure-web-lab-dev.conf)) —
`staging`/`prod` suivront une fois ce socle vérifié. Le `location /api/`
inclut aussi `snippets/rate-limiting.conf` : le rate limiting protège
déjà l'API sans configuration supplémentaire (zone partagée avec le reste
du site, voir [`nginx/README.md`](../../nginx/README.md#rate-limiting)).
`/api/auth/login` a en plus sa propre zone, bien plus stricte
(`snippets/rate-limiting-login.conf`, `location =` donc prioritaire sur
le préfixe `/api/`) — voir la section Authentification ci-dessus.

## Lancer en local

```bash
./scripts/setup-postgres-db.sh   # si pas déjà fait
./scripts/setup-db-schema.sh     # crée les tables users / audit_log
cd app/backend
npm install                      # installe bcrypt, express-session, connect-pg-simple
npm start
```

`DATABASE_URL` généré par
[`scripts/setup-postgres-db.sh`](../../scripts/setup-postgres-db.sh) ;
`SESSION_SECRET` à ajouter soi-même dans `.env` (`openssl rand -hex 32`,
voir [`.env.example`](.env.example)) — aucun script ne le génère
automatiquement pour l'instant, contrairement au mot de passe DB.

`bcrypt` est un module natif (compilé à l'installation) : si `npm
install` échoue dessus, installer `build-essential` et `python3`
(`sudo apt-get install -y build-essential python3`) avant de réessayer.

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

Backend confirmé fonctionnel et connecté à PostgreSQL.

Exécuté (à travers Nginx, reverse proxy) :

```text
$ curl -sk --resolve dev.secure-web-lab.local:8443:127.0.0.1 \
    https://dev.secure-web-lab.local:8443/api/health
{"status":"ok","db":"ok"}
```

**Socle vérifié de bout en bout** : Node ↔ PostgreSQL ↔ Nginx (TLS,
reverse proxy, rate limiting hérité).

### Vérification du flux d'authentification

À travers Nginx, avec un fichier de cookies pour garder la session entre
les appels :

```bash
BASE="https://dev.secure-web-lab.local:8443"
RESOLVE="--resolve dev.secure-web-lab.local:8443:127.0.0.1"
JAR=/tmp/cookies.txt

# Inscription (connecte automatiquement)
curl -sk $RESOLVE -c $JAR -H 'Content-Type: application/json' \
  -d '{"email":"test@example.com","password":"une-phrase-de-passe-suffisamment-longue"}' \
  "$BASE/api/auth/register"

# Session courante
curl -sk $RESOLVE -b $JAR "$BASE/api/auth/me"

# Route admin : doit échouer (rôle "user" par défaut)
curl -sk $RESOLVE -b $JAR -o /dev/null -w "%{http_code}\n" "$BASE/api/admin/ping"

# Promotion admin, puis reconnexion pour rafraîchir la session
./scripts/promote-admin.sh test@example.com
curl -sk $RESOLVE -c $JAR -H 'Content-Type: application/json' \
  -d '{"email":"test@example.com","password":"une-phrase-de-passe-suffisamment-longue"}' \
  "$BASE/api/auth/login"
curl -sk $RESOLVE -b $JAR "$BASE/api/admin/ping"

# Déconnexion, puis /me doit redevenir 401
curl -sk $RESOLVE -b $JAR -o /dev/null -w "%{http_code}\n" -X POST "$BASE/api/auth/logout"
curl -sk $RESOLVE -b $JAR -o /dev/null -w "%{http_code}\n" "$BASE/api/auth/me"
```

Attendu, dans l'ordre : `201` (register, corps avec `role":"user"`),
`{"id":...,"role":"user"}` (me), `403` (admin/ping avant promotion),
promotion affichée avec `role | admin`, `200` avec `role":"admin"`
(login), `{"pong":true,"role":"admin"}` (admin/ping après), `204`
(logout), `401` (me après logout).

*(sortie réelle à ajouter ici après exécution)*
