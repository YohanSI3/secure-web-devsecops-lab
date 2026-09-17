# Backend — documentation technique

Choix d'implémentation concrets du backend applicatif (Phase 5 du
`ToDo.md`, IAM). Pour le fonctionnement général de Node.js/npm et de
PostgreSQL, voir [`Notes/nodejs/`](../../Notes/nodejs/README.md) et
[`Notes/postgresql/`](../../Notes/postgresql/README.md).

## État actuel

Phase 5 (IAM) complète côté items obligatoires du `ToDo.md` : socle
(connexion DB, reverse proxy Nginx, healthcheck), authentification
([`src/routes/auth.js`](src/routes/auth.js) : `POST /auth/register`,
`POST /auth/login`, `POST /auth/logout`, `GET /auth/me`,
`POST /auth/forgot-password`, `POST /auth/reset-password`), RBAC
([`src/routes/admin.js`](src/routes/admin.js), `GET /admin/ping`) —
tous vérifiés en conditions réelles, voir Vérification plus bas. MFA
volontairement laissé en évolution future (voir
[`Notes/iam/README.md`](../../Notes/iam/README.md#mfa--pas-dans-cette-phase-évolution-possible)) :
marqué "option" dans le `ToDo.md`, pas requis pour clore la phase.

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

**Bug réel : dépendance transitive vulnérable, corrigé par montée de
version, pas contournement.** `npm audit` a signalé `tar` (critique) via
`bcrypt@5.1.1` → `@mapbox/node-pre-gyp` (outil qui télécharge/compile le
binaire natif de `bcrypt` **à l'installation** — jamais exécuté par l'app
en marche). `npm audit fix` n'a rien pu faire : `node-pre-gyp` fige une
plage de `tar` trop ancienne pour qu'un correctif non cassant existe dans
cet arbre de dépendances. Plutôt que forcer une résolution
(`npm audit fix --force`, qui aurait pu imposer une version de `bcrypt`
incompatible sans contrôle), vérifié que `bcrypt@6.0.0` a **supprimé**
`node-pre-gyp` (donc `tar`) au profit de binaires précompilés livrés
directement dans le paquet (`prebuildify`) — changelog confirmé sans
changement d'API (`hash`/`compare` identiques), seule exigence
`Node.js >= 16` (largement couvert par la Node 24 LTS de ce lab). Une
vraie suppression de la dépendance vulnérable, pas un contournement.

Confirmé après montée de version :

```text
$ npm install
added 1 package, removed 57 packages, changed 2 packages
found 0 vulnerabilities
$ npm audit
found 0 vulnerabilities
$ npm start
backend listening on 127.0.0.1:3000
```

57 paquets supprimés d'un coup (toute la chaîne
`node-pre-gyp`/`tar`/`rimraf`/`glob` ancien) pour 1 seul ajouté
(`node-gyp-build`) — confirme que ce n'était pas juste `tar` qui était
disproportionné dans l'arbre de dépendances, mais tout un outillage de
compilation devenu inutile.

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
email inconnu), inscription, déconnexion, et maintenant demande/succès de
réinitialisation de mot de passe est journalisée dans `audit_log` (voir
[`db/schema.sql`](db/schema.sql)) — `user_id` peut être `null` (email
inconnu à la connexion) sans jamais bloquer l'écriture de la trace
elle-même.

### Réinitialisation de mot de passe (`forgot-password` / `reset-password`)

Jeton à usage unique (`crypto.randomBytes(32)`, 256 bits), valable 30
minutes, **haché en SHA-256** avant stockage dans
`password_reset_tokens` (voir [`db/schema.sql`](db/schema.sql)) — pas en
clair, même logique que les mots de passe, mais SHA-256 plutôt que bcrypt
puisque le jeton est déjà de la haute entropie générée par machine, pas
un secret à faible entropie choisi par un humain à protéger du
brute-force. Détail complet dans
[`Notes/iam/reinitialisation-mot-de-passe.md`](../../Notes/iam/reinitialisation-mot-de-passe.md).

- **Même réponse générique** (`{"message":"if_account_exists_email_sent"}`,
  toujours `200`) que l'email existe ou non — même résistance à
  l'énumération que la connexion.
- **Origine de l'URL reconstruite depuis la requête** (`req.protocol`
  + `req.get('host')`), pas une valeur fixe en config : une seule
  instance Node sert les trois environnements (dev/staging/prod) via
  trois hôtes différents ; Nginx transmet déjà le bon `Host` et le bon
  `X-Forwarded-Proto` (voir `trust proxy` plus haut), donc le lien de
  reset pointe automatiquement vers le bon environnement sans code
  spécifique à chacun.
- **Coupe toutes les sessions actives du compte** au moment du reset
  réussi (`DELETE FROM session WHERE sess->>'userId' = ...`) — un reset
  suppose souvent un compte déjà compromis ; sans ça, une session ouverte
  par un attaquant avec l'ancien mot de passe resterait valide après le
  changement.
- **Mailpit** comme serveur SMTP local ([`src/mail.js`](src/mail.js),
  [`scripts/install-mailpit.sh`](../../scripts/install-mailpit.sh)) :
  capture les emails sortants sans jamais les délivrer, pour tester tout
  le flux (y compris cliquer un vrai lien reçu) sans dépendre d'un
  fournisseur ni risquer d'envoyer un email réel. Service dédié, tourne
  sous son propre utilisateur système (`mailpit`), lié à `127.0.0.1`
  uniquement (SMTP **et** interface web) — jamais exposé via Nginx :
  consulter les emails capturés se fait directement sur la machine
  (`curl http://127.0.0.1:8025/...` ou un tunnel local), pas depuis le
  site public. Voir
  [`Notes/devsecops/paysage-outillage.md`](../../Notes/devsecops/paysage-outillage.md)
  pour les vrais fournisseurs (payants) que Mailpit remplace ici.
- **Pages statiques** [`app/static-site/forgot-password.html`](../static-site/forgot-password.html)
  et [`reset-password.html`](../static-site/reset-password.html), avec
  leur JS respectif dans des fichiers **externes**
  (`forgot-password.js`/`reset-password.js`) — jamais en `<script>`
  inline : la CSP de ce lab
  ([`nginx/snippets/security-headers.conf`](../../nginx/snippets/security-headers.conf),
  `default-src 'self'`) bloque tout script en ligne sans
  `'unsafe-inline'`, jamais ajouté volontairement (même raison que le
  CSS déjà externalisé sur `index.html` depuis la Phase 1).

## Nginx : `/api/` en reverse proxy

[`nginx/snippets/api-proxy.conf`](../../nginx/snippets/api-proxy.conf),
désormais inclus dans les **trois** vhosts (`dev`, `staging`, `prod` —
initialement dev seul le temps de vérifier le socle, étendu maintenant
que c'est fait). Une seule instance Node partagée par les trois, comme
pour le site statique et le rate limiting (voir
[`Notes/nginx/environnements/`](../../Notes/nginx/environnements/README.md)) —
pas trois backends séparés. Le `location /api/` inclut aussi
`snippets/rate-limiting.conf` : le rate limiting protège déjà l'API sans
configuration supplémentaire (zone partagée avec le reste du site, voir
[`nginx/README.md`](../../nginx/README.md#rate-limiting)).
`/api/auth/login`, `/api/auth/forgot-password` et
`/api/auth/reset-password` ont chacune leur propre `location =`
pointant vers la zone bien plus stricte `snippets/rate-limiting-login.conf`
(prioritaire sur le préfixe `/api/` pour ces trois routes précises) —
les trois sont des cibles plausibles d'abus (brute-force de connexion,
spam d'emails de reset, brute-force du jeton de reset), pas seulement la
connexion.

**Bug réel, trouvé au premier test de bout en bout de la réinitialisation** :
`POST /api/auth/forgot-password` renvoyait `Cannot POST /` (le 404 par
défaut d'Express pour une route qu'il ne connaît pas), alors que la route
`POST /auth/forgot-password` existe bien côté backend. Cause : les trois
`location = /api/auth/...` incluaient `snippets/api-proxy.conf`, qui
contient `proxy_pass http://127.0.0.1:3000/;` (URI finale avec `/`). Ce
`proxy_pass` avec URI finale a un comportement de **substitution de
préfixe** : nginx retire de l'URI entrante la portion couverte par la
`location`, puis remplace par l'URI finale. Pour `location /api/`
(préfixe), la portion couverte est bien le préfixe `/api/` : une requête
sur `/api/health` devient `/health` côté backend — comportement voulu.
Mais pour `location = /api/auth/login` (correspondance **exacte**), toute
l'URI `/api/auth/login` est "la portion couverte" par la location — donc
entièrement retirée et remplacée par `/`, peu importe la route réelle.
Le backend recevait donc `POST /` sur les trois routes d'authentification
sensibles, jamais `/auth/login` ni `/auth/forgot-password`.

Corrigé en séparant les en-têtes communs
([`nginx/snippets/api-proxy-headers.conf`](../../nginx/snippets/api-proxy-headers.conf),
sans `proxy_pass`) du `proxy_pass` lui-même : `api-proxy.conf` garde
`proxy_pass http://127.0.0.1:3000/;` pour le préfixe `/api/`, et chacune
des trois `location =` déclare désormais son propre `proxy_pass` explicite
et complet (`proxy_pass http://127.0.0.1:3000/auth/login;`, etc.) plutôt
que de réutiliser `api-proxy.conf` tel quel. Un `proxy_pass` sans
substitution de préfixe (URI fixe, indépendante de ce que la `location`
a matché) est le comportement correct pour une correspondance exacte.
Trouvé en testant réellement le flux (curl → `Cannot POST /` reçu tel
quel, pas juste supposé), pas en relisant la config à froid.

## Lancer en local

```bash
./scripts/setup-postgres-db.sh   # si pas déjà fait
./scripts/setup-db-schema.sh     # crée/met à jour les tables (users, audit_log, password_reset_tokens)
./scripts/install-mailpit.sh     # si pas déjà fait -- capteur SMTP local
cd app/backend
npm install                      # installe bcrypt, express-session, connect-pg-simple, nodemailer
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

Exécuté (deux comptes de test, `test@example.com` promu admin et
`test2@example.com` resté simple utilisateur pour vérifier le refus RBAC
sans avoir à démonter la session admin en cours) :

```text
$ curl .../auth/register   {email: test@example.com}
{"id":"1","email":"test@example.com","role":"user"}

$ curl .../auth/me
{"id":"1","role":"user"}

$ ./scripts/promote-admin.sh test@example.com
UPDATE 1
 id |      email       | role
----+------------------+-------
  1 | test@example.com | admin

$ curl .../auth/login   {email: test@example.com}
{"id":"1","email":"test@example.com","role":"admin"}

$ curl .../admin/ping
{"pong":true,"role":"admin"}

$ curl -X POST .../auth/logout
204

$ curl .../auth/me
401

# Second compte, resté "user", pour vérifier le refus RBAC :
$ curl .../auth/register   {email: test2@example.com}
{"id":"2","email":"test2@example.com","role":"user"}

$ curl .../admin/ping
403
```

**Flux complet confirmé** : inscription auto-connectée, session
persistante à travers Nginx, refus RBAC (`403`) pour un rôle
insuffisant, acceptation (`200`) après promotion et reconnexion,
déconnexion effective (`401` sur `/me` ensuite).

Détail à noter, pas un bug : `"id":"1"` est une **chaîne**, pas un
nombre — le driver `pg` sérialise les colonnes `BIGINT`/`BIGSERIAL` en
`string` par défaut (un nombre JavaScript ne représente pas exactement
tous les entiers 64 bits) plutôt qu'en `number`, qui perdrait
silencieusement de la précision au-delà de 2^53. Comportement voulu du
driver, à garder en tête côté client de l'API plutôt qu'à "corriger".

### Vérification de la réinitialisation de mot de passe

Nouveau fichier `conf.d`-like côté Nginx (nouvelles `location =` dans les
3 vhosts) : redéployer avant de tester.

```bash
./scripts/deploy-nginx-config.sh dev
./scripts/deploy-nginx-config.sh staging
./scripts/deploy-nginx-config.sh prod
```

```bash
BASE="https://dev.secure-web-lab.local:8443"
RESOLVE="--resolve dev.secure-web-lab.local:8443:127.0.0.1"

# Déclenche l'email (compte test@example.com déjà créé plus haut)
curl -sk $RESOLVE -H 'Content-Type: application/json' \
  -d '{"email":"test@example.com"}' \
  "$BASE/api/auth/forgot-password"

# Lire l'email capturé par Mailpit (dernier message reçu)
curl -s http://127.0.0.1:8025/api/v1/messages | grep -o '"ID":"[^"]*"' | head -1
# puis, avec l'ID trouvé :
curl -s "http://127.0.0.1:8025/api/v1/message/<ID>" | grep -o 'token=[a-f0-9]*'

# Réinitialiser avec le jeton extrait de l'email
curl -sk $RESOLVE -H 'Content-Type: application/json' \
  -d '{"token":"<TOKEN>","password":"un-nouveau-mot-de-passe-suffisamment-long"}' \
  "$BASE/api/auth/reset-password"

# L'ancien mot de passe ne doit plus fonctionner
curl -sk $RESOLVE -H 'Content-Type: application/json' \
  -d '{"email":"test@example.com","password":"une-phrase-de-passe-suffisamment-longue"}' \
  -o /dev/null -w "ancien mdp -> %{http_code}\n" \
  "$BASE/api/auth/login"

# Le nouveau doit fonctionner
curl -sk $RESOLVE -H 'Content-Type: application/json' \
  -d '{"email":"test@example.com","password":"un-nouveau-mot-de-passe-suffisamment-long"}' \
  -o /dev/null -w "nouveau mdp -> %{http_code}\n" \
  "$BASE/api/auth/login"
```

Attendu : `forgot-password` renvoie `{"message":"if_account_exists_email_sent"}`,
un email apparaît dans Mailpit avec un lien contenant le jeton,
`reset-password` renvoie `204`, l'ancien mot de passe échoue (`401`), le
nouveau fonctionne (`200`).

Exécuté (après correctif du bug `proxy_pass` documenté plus haut) :

```text
$ curl ... "$BASE/api/auth/forgot-password"   {email: test@example.com}
{"message":"if_account_exists_email_sent"}

$ curl -s http://127.0.0.1:8025/api/v1/messages | grep -o '"ID":"[^"]*"' | head -1
"ID":"6NZyTHn4CfC1Tcgkq6Cd65"

$ curl -s "http://127.0.0.1:8025/api/v1/message/6NZyTHn4CfC1Tcgkq6Cd65" | grep -o 'token=[a-f0-9]*'
token=<TOKEN redacted -- jeton réel à usage unique, déjà consommé par le reset ci-dessous>

$ curl ... "$BASE/api/auth/reset-password"   {token: ..., password: "un-nouveau-mot-de-passe-suffisamment-long"}
(corps vide -- 204 No Content)

$ curl ... "$BASE/api/auth/login"   {email: test@example.com, password: "une-phrase-de-passe-suffisamment-longue" (ancien)}
ancien mdp -> 401

$ curl ... "$BASE/api/auth/login"   {email: test@example.com, password: "un-nouveau-mot-de-passe-suffisamment-long" (nouveau)}
nouveau mdp -> 200
```

**Flux complet confirmé de bout en bout** : email capturé par Mailpit avec
jeton valide, réinitialisation acceptée (`204`), ancien mot de passe
immédiatement rejeté (`401`), nouveau mot de passe fonctionnel (`200`).
Premier essai réel bloqué par le bug `proxy_pass` ci-dessus (`Cannot
POST /` avant même d'atteindre Mailpit) ; ce second essai, après
correctif, est le premier succès de bout en bout de ce flux.
