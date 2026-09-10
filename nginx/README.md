# Nginx — documentation technique

Choix d'implémentation concrets pour la configuration Nginx de ce lab. Pour
le fonctionnement général des concepts TLS/HTTP sous-jacents, voir
[`Notes/nginx/`](../Notes/nginx/README.md) (TLS, headers, environnements,
utilisateur dédié).

## `conf.d/` vs `snippets/` : quand utiliser lequel

- **`conf.d/`** — directives déclarées **une seule fois**, qui s'appliquent
  **automatiquement par héritage** à tous les server blocks en dessous
  (y compris les blocs HTTP de redirection), sans étape d'inclusion à
  faire ni à oublier ailleurs. Ex. [`request-limits.conf`](conf.d/request-limits.conf)
  (`client_max_body_size` etc.) : on veut cette protection partout sans
  exception, autant le garantir structurellement.
- **`snippets/`** — directives qui doivent être **explicitement incluses à
  l'endroit précis** où leur effet doit s'appliquer, pour l'une de ces
  raisons :
  - Nginx l'exige techniquement côté déclaration/usage séparés :
    `limit_req_zone` ne se déclare qu'au niveau http et n'active rien tant
    qu'un `limit_req zone=...;` n'est pas écrit là où on veut l'appliquer —
    voir [`rate-limiting.conf`](snippets/rate-limiting.conf), inclus dans
    le `location /` de chaque vhost ;
  - Nginx l'exige techniquement côté syntaxe : un bloc `location {}` ne
    peut exister qu'**à l'intérieur** d'un bloc `server {}`, jamais
    directement au niveau http — donc même une directive par ailleurs
    "globale" comme `error_page` doit passer par un snippet dès qu'elle
    s'accompagne d'un `location` (voir
    [`custom-error-pages.conf`](snippets/custom-error-pages.conf)) ;
  - choix délibéré de contrôle explicite (`tls-hardening.conf`,
    `security-headers.conf`).

Repère rapide : si la directive a une déclaration ET une application
séparées (zone puis usage), l'application va en `snippets/` même si la
déclaration reste en `conf.d/`. Si la directive s'applique directement là
où elle est définie, `conf.d/` suffit.

## Protection contre divulgation de version

`server_tokens off;` ([`conf.d/security.conf`](conf.d/security.conf),
Phase 1) supprime déjà le numéro de version Nginx du header `Server:` et
du pied de page des pages d'erreur par défaut — mais ce pied de page
continue d'afficher le mot **« nginx »** tout court (sans version), et le
header `Server:` répond toujours `nginx` : l'identité du logiciel reste
exposée, seule sa version disparaît.
[`snippets/custom-error-pages.conf`](snippets/custom-error-pages.conf) va
un cran plus loin sur les pages d'erreur (le header `Server: nginx` seul,
lui, ne peut pas être supprimé/réécrit sans module tiers — voir plus bas) :

```nginx
error_page 403 404 405 413 429 500 502 503 504 /error.html;

location = /error.html {
    internal;
}
```

- **Une page générique unique** plutôt qu'une page par code d'erreur :
  [`app/static-site/error.html`](../app/static-site/error.html), sans
  aucune mention de Nginx ni de la stack technique, réutilisée pour tous
  les codes listés. Le code HTTP réel renvoyé au client n'est **pas**
  affecté par `error_page` (pas de suffixe `=200` ici) : `curl -w
  "%{http_code}"` continue de voir `404`, `429`, `413`, etc. — seul le
  **corps** de la réponse change, pas le code transmis au client. Un site
  réel distinguerait probablement les messages par code (« page introuvable »
  vs « trop de requêtes ») ; une page unique reste volontairement plus
  simple ici, le point démontré est l'absence de fuite d'identité
  logicielle, pas le raffinement du message.
- **Codes choisis** : uniquement ceux que ce site peut réellement produire
  au vu de sa config actuelle — `404`/`405` (routage statique, méthode non
  supportée par le module de fichiers statiques, cf.
  [`Notes/nginx/controle-tailles-requetes/`](../Notes/nginx/controle-tailles-requetes/README.md)),
  `413`/`429` (contrôle de taille et rate limiting, ci-dessous), `403`
  (permissions), `500`/`502`/`503`/`504` (erreurs serveur génériques,
  gardées par réalisme même si peu probables sans backend proxifié).
- **`location = /error.html { internal; }`** — empêche qu'un client
  demande cette page directement (`GET /error.html` répondrait `404`,
  Nginx la réserve aux redirections internes déclenchées par
  `error_page`). N'hérite pas de `snippets/rate-limiting.conf` (absent de
  ce `location`) : servir une page d'erreur ne doit pas elle-même
  consommer/déclencher le quota de rate limiting du client.

**Limite connue, assumée** : le header `Server: nginx` (sans version)
reste présent sur *toutes* les réponses, succès compris — Nginx ne permet
pas nativement de le supprimer ou de le réécrire ; il faudrait soit un
module tiers non officiel (`headers-more`, hors des dépôts Ubuntu
utilisés par [`scripts/install-nginx.sh`](../scripts/install-nginx.sh),
casserait la reproductibilité par paquet déjà en place), soit recompiler
Nginx depuis les sources en modifiant sa chaîne de version — les deux
hors de portée d'un simple ajustement de configuration, et non retenus ici
pour cette raison.

## Journalisation avancée

[`conf.d/logging.conf`](conf.d/logging.conf) (niveau http, même logique
déclaration/application que `limit_req_zone` — un `log_format` déclaré ici
ne s'active nulle part tant qu'il n'est pas référencé explicitement dans
un `access_log` de vhost) :

```nginx
log_format security_log
    '$remote_addr - $remote_user [$time_local] '
    '"$request" $status $body_bytes_sent '
    '"$http_referer" "$http_user_agent" '
    'rt=$request_time ssl="$ssl_protocol/$ssl_cipher" '
    'req_id=$request_id';
```

Référencé dans chaque vhost (ex. dev) :

```nginx
add_header X-Request-Id $request_id always;

access_log /var/log/nginx/secure-web-lab-dev.access.log security_log;
error_log  /var/log/nginx/secure-web-lab-dev.error.log warn;
```

- **Format étendu plutôt que le `combined` implicite par défaut** — garde
  la structure standard (compatible avec les outils qui savent déjà lire
  du `combined`) et ajoute trois champs utiles absents par défaut :
  - `rt=$request_time` — temps de traitement de la requête, utile pour
    repérer une dégradation de performance sans corréler avec un outil
    externe ;
  - `ssl="$ssl_protocol/$ssl_cipher"` — protocole/suite réellement
    négociés pour cette connexion précise, vérifiable directement dans le
    log plutôt qu'en devant reproduire un test `curl -v` a posteriori
    (rejoint [suites de chiffrement](#suites-de-chiffrement) ci-dessus).
    Vide (`ssl="/"`) sur les entrées des blocs HTTP de redirection
    (80/8080/8081), qui ne négocient aucun TLS — attendu, pas une erreur.
  - `req_id=$request_id` — identifiant unique généré par Nginx pour
    chaque requête (variable core, aucun module requis), **répété dans le
    header de réponse** `X-Request-Id` : permet de retrouver la ligne de
    log exacte correspondant à une réponse précise reçue par un client,
    sans avoir à corréler par timestamp approximatif.
- **`limit_req_log_level warn;`** (dans
  [`conf.d/rate-limiting.conf`](conf.d/rate-limiting.conf)) — un rejet par
  rate limiting est une application de politique attendue, pas une panne :
  `warn` plutôt que le `error` par défaut de ce module.
- **`error_log ... warn;` explicite sur chaque vhost** — changement
  **nécessaire** pour que le point précédent ait un effet : `error_log`
  ne retient par défaut que les messages de niveau `error` et plus grave,
  donc des messages `limit_req` remontés en `warn` resteraient
  silencieusement absents du fichier sans ce changement de seuil ici
  aussi. Un des deux réglages sans l'autre aurait semblé fonctionner (pas
  d'erreur de syntaxe) tout en ne produisant aucune ligne — piège
  d'ordre de sévérité repéré avant déploiement plutôt qu'après coup en se
  demandant pourquoi le fichier reste vide.

## Timeouts adaptés

[`conf.d/timeouts.conf`](conf.d/timeouts.conf) (niveau http, même logique
que `request-limits.conf` — voir la règle `conf.d/` vs `snippets/`
ci-dessus) :

```nginx
client_header_timeout 10s;
client_body_timeout   10s;
send_timeout 10s;
keepalive_timeout 65s;
```

- **`client_header_timeout`/`client_body_timeout` à `10s`** (défaut Nginx :
  `60s`) — resserrés pour limiter l'exposition à une attaque par lenteur
  volontaire (type *Slowloris* : maintenir des connexions ouvertes en
  envoyant les en-têtes/le corps un octet à la fois, pour épuiser le
  nombre de connexions disponibles). `10s` reste largement suffisant pour
  un usage réel — l'envoi d'en-têtes/d'un petit corps de requête se fait en
  pratique en millisecondes, pas en secondes, même sur une connexion
  lente ; voir
  [`Notes/nginx/timeouts/README.md`](../Notes/nginx/timeouts/README.md)
  pour la limite réelle de cette protection.
- **`send_timeout 10s`** — même logique côté écriture de la réponse : un
  client qui cesse de lire (délibérément ou par lenteur anormale) libère
  la connexion après 10s d'inactivité en écriture plutôt que de la retenir
  jusqu'à 60s.
- **`keepalive_timeout 65s`** — légèrement sous le défaut Nginx (`75s`) :
  libère un peu plus tôt les connexions keep-alive inactives (donc le slot
  de connexion associé) sans impact perceptible sur un usage réel — une
  session de navigation normale enchaîne ses requêtes bien en dessous de
  ce délai.

## Contrôle des tailles de requêtes

[`conf.d/request-limits.conf`](conf.d/request-limits.conf) (niveau http,
s'applique donc aussi aux server blocks HTTP de redirection, pas
seulement aux vhosts HTTPS) :

```nginx
client_max_body_size 100k;
client_body_buffer_size 16k;
client_header_buffer_size 1k;
large_client_header_buffers 4 8k;
```

- **`client_max_body_size 100k`** — largement en dessous du défaut Nginx
  (`1m`), assumé délibérément : [`app/static-site/`](../app/static-site/)
  ne reçoit aucun upload ni formulaire, une limite basse ferme cette
  surface sans retirer de fonctionnalité réelle — cohérent avec l'objectif
  d'un site réaliste plutôt qu'artificiellement bridé (le contraire de
  l'item retiré du `ToDo.md` sur les méthodes HTTP : ici on borne une
  ressource qu'aucun usage légitime du site n'utilise, on ne retire rien
  qu'un vrai visiteur attendrait).
- **`client_body_buffer_size 16k`** — valeur par défaut de Nginx sur
  Linux 64 bits, gardée telle quelle : les corps de requête plus petits que
  ce seuil restent en mémoire, les plus gros (jusqu'à `client_max_body_size`)
  débordent vers les fichiers temporaires de
  [`/var/lib/nginx/body`](../Notes/nginx/utilisateur-dedie/permissions-et-repertoires-temporaires.md)
  déjà repris par l'utilisateur dédié aux workers.
- **`client_header_buffer_size`** / **`large_client_header_buffers`** —
  valeurs par défaut de Nginx, déclarées ici explicitement (traçabilité)
  plutôt que laissées implicites : bornent la ligne de requête et les
  en-têtes, une surface différente du corps de requête (un en-tête
  anormalement long — cookie surdimensionné, en-tête forgé — n'a pas
  besoin d'un corps de requête pour poser problème).

## Rate limiting

[`conf.d/rate-limiting.conf`](conf.d/rate-limiting.conf) (niveau http,
obligatoire pour `limit_req_zone`) :

```nginx
limit_req_zone $binary_remote_addr zone=lab:10m rate=10r/s;
limit_req_status 429;
```

[`snippets/rate-limiting.conf`](snippets/rate-limiting.conf) (appliqué dans
le `location /` de chaque vhost) :

```nginx
limit_req zone=lab burst=20 nodelay;
```

- **Une seule zone partagée entre dev/staging/prod**, pas trois zones
  distinctes : les trois vhosts sont servis par la **même** instance Nginx
  (mêmes workers, cf.
  [`Notes/nginx/environnements/`](../Notes/nginx/environnements/README.md)),
  donc une IP qui teste dev intensivement puis bascule sur prod partage de
  toute façon la même machine/capacité réelle — refléter ça par un budget
  par IP partagé est plus honnête qu'une isolation artificielle par
  environnement qui ne correspondrait à aucune isolation réelle des
  ressources.
- **`rate=10r/s`, `burst=20`, `nodelay`** — volontairement généreux : ce
  lab doit rester utilisable comme un site normal (voir
  [[feedback_lab_doit_rester_realiste]] dans les principes du projet — pas
  de durcissement qui casserait un usage réaliste). Un chargement de page
  normal (`index.html` + `style.css`, 2 requêtes) ne s'approche pas du
  seuil ; la protection cible les rafales largement anormales (scan, test
  de charge non maîtrisé), pas la navigation légitime. `nodelay` sert les
  requêtes dans le burst immédiatement plutôt que de les mettre en file
  d'attente — évite d'introduire une latence artificielle sur un
  chargement de page normal (plusieurs requêtes quasi simultanées par le
  navigateur).
- **`limit_req_status 429`** plutôt que le `503` par défaut de Nginx :
  distingue, pour un client réel, « vous envoyez trop vite » (429, avec
  la sémantique RFC 6585 associée) de « le serveur est en panne » (503) —
  encore une fois cohérent avec l'objectif de site réaliste plutôt qu'un
  comportement qui ne dirait rien d'utile à un vrai client.
- **Complémentaire de fail2ban, pas redondant** : `limit_req` réagit
  **instantanément**, requête par requête, à un débit anormal, quel que
  soit le code de retour (200 compris) ; `nginx-404-flood`
  ([`fail2ban/README.md`](../fail2ban/README.md)) réagit **après coup**, sur
  un nombre d'échecs (404) cumulés dans une fenêtre de plusieurs minutes.
  Un scan lent qui reste sous le seuil fail2ban peut dépasser le débit
  instantané ; une rafale de requêtes valides ne déclenche jamais
  fail2ban mais peut déclencher `limit_req`.

## Suites de chiffrement

[`snippets/tls-hardening.conf`](snippets/tls-hardening.conf) :

```nginx
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers off;
```

Liste réduite à 6 suites, toutes ECDHE + AEAD (GCM ou ChaCha20-Poly1305) —
équivalent du profil « Intermediate » du générateur Mozilla SSL Config,
moins les suites de repli `DHE-RSA-*`. Choix documenté :

- **Aucune suite `DHE-RSA-*` de repli** : ces suites servent aux clients
  incapables de négocier ECDHE (très rares aujourd'hui) et nécessitent de
  générer et servir un `ssl_dhparam` (paramètres Diffie-Hellman, fichier
  supplémentaire à maintenir) pour un bénéfice nul dans ce lab — aucun
  client à supporter en dehors de navigateurs/`curl` récents.
- **`ssl_prefer_server_ciphers off`** : sans effet de sécurité réel ici
  puisque les 6 suites restantes sont toutes considérées sûres — imposer
  un ordre serveur n'a de sens que pour prioriser une suite faible sur une
  autre, ce qui ne s'applique pas à une liste déjà entièrement filtrée.
- **TLS 1.3 non concerné par `ssl_ciphers`** : ses suites (toutes AEAD,
  toutes avec (EC)DHE) sont fixées par la norme elle-même, pas
  configurables côté serveur — seul TLS 1.2 lit `ssl_ciphers`.

## Reprise de session

```nginx
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;
ssl_session_tickets off;
```

- **`shared:SSL:10m`** — cache **partagé entre workers** (indispensable :
  chaque worker est un processus séparé, un cache non partagé serait
  quasi inutile puisqu'une reconnexion arrivant sur un autre worker ne
  trouverait jamais la session). ~10 Mo suffit très largement au trafic de
  ce lab.
- **`ssl_session_tickets off`** — désactivé délibérément plutôt qu'activé
  par défaut. Les tickets de session sont chiffrés par une clé que nginx
  génère lui-même par worker au démarrage, sans rotation automatique ; une
  fuite ou une réutilisation prolongée de cette clé permettrait de
  déchiffrer rétroactivement des sessions passées, contournant la forward
  secrecy pourtant obtenue par ECDHE. Sans mécanisme de rotation de clé
  explicitement mis en place (hors périmètre de ce lab), le cache de
  session partagé seul est le choix le plus sûr — recommandation reprise
  du profil Mozilla « Intermediate ».

## HSTS preload

[`snippets/security-headers.conf`](snippets/security-headers.conf) :

```nginx
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
```

`preload` ajouté à la valeur du header existant (voir
[`Notes/nginx/headers-securite/`](../Notes/nginx/headers-securite/README.md)
pour ce que HSTS fait déjà sans lui). **Non soumis** à la liste de
préchargement des navigateurs (hstspreload.org) : la soumission exige un
nom de domaine public réel et résolvable, incompatible avec
`secure-web-lab.local`/`dev.secure-web-lab.local`/etc., qui ne sont que des
entrées locales sans existence DNS publique. Le header est correct dans sa
syntaxe (condition nécessaire à une soumission) mais reste ici un exercice
de configuration, pas une inscription réelle. Voir
[`Notes/nginx/tls/durcissement-suites-ocsp-resumption.md`](../Notes/nginx/tls/durcissement-suites-ocsp-resumption.md)
pour le risque particulier de `preload` sur un vrai domaine (retrait très
lent une fois inscrit).

## OCSP stapling

Documenté et écrit en commentaire dans
[`snippets/tls-hardening.conf`](snippets/tls-hardening.conf), **non
activé** :

```nginx
# ssl_stapling on;
# ssl_stapling_verify on;
# ssl_trusted_certificate /etc/nginx/ssl/<env>/ca.crt;
# resolver 1.1.1.1 8.8.8.8 valid=300s;
# resolver_timeout 5s;
```

Raison : OCSP stapling suppose que l'autorité de certification exploite un
**répondeur OCSP** (un service qui répond « ce certificat est-il toujours
valide ? »), dont l'URL est embarquée dans le certificat serveur lui-même.
La CA locale de ce lab ([`scripts/generate-local-ca.sh`](../scripts/generate-local-ca.sh))
est auto-signée et ne fait tourner aucun répondeur — activer
`ssl_stapling` produirait uniquement des tentatives de requête échouées
dans les logs d'erreur Nginx, sans aucun bénéfice, ni réel signal à
observer. Contrairement à HSTS preload (qui reste au moins syntaxiquement
démontrable), l'OCSP stapling n'a ici **rien à démontrer en pratique** tant
que le lab reste sur une CA auto-signée — la config ci-dessus n'est
qu'une référence prête à l'emploi pour une bascule future vers un
certificat émis par une CA publique (Let's Encrypt, typiquement).

## Déployer ces changements

Le TLS/HSTS vit dans des fichiers `snippets/` déjà reliés à `/etc/nginx/`
par [`scripts/deploy-nginx-config.sh`](../scripts/deploy-nginx-config.sh) —
éditer leur contenu ne demande qu'un reload. Le rate limiting ajoute en
revanche un **nouveau** fichier (`conf.d/rate-limiting.conf`), pas encore
symlinké côté machine cible, et modifie les 3 fichiers
`sites-available/*.conf` (déjà symlinkés, l'édition suffit) : il faut donc
relancer le script de déploiement de config au moins une fois pour créer
le nouveau symlink, pas seulement recharger.

```bash
./scripts/deploy-nginx-config.sh dev
./scripts/deploy-nginx-config.sh staging
./scripts/deploy-nginx-config.sh prod
```

(inclut déjà `nginx -t` et `systemctl reload nginx` — voir le script.)

## Vérification

### TLS (suites, session, HSTS)

```bash
curl -sk -v --resolve secure-web-lab.local:443:127.0.0.1 \
  https://secure-web-lab.local/ 2>&1 | grep -iE 'SSL connection|Cipher|strict-transport'
```

Attendu : une suite `ECDHE-*-GCM-*` ou `ECDHE-*-CHACHA20-*` (TLS 1.2) ou
`TLS_AES_*`/`TLS_CHACHA20_*` (TLS 1.3 — nom de suite différent car négocié
indépendamment de `ssl_ciphers`), et le header HSTS se terminant par
`; preload`.

Exécuté :

```text
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384 / X25519 / RSASSA-PSS
< Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
```

Client et serveur ont négocié TLS 1.3 (curl le préfère par défaut quand
les deux en sont capables) avec `X25519` comme courbe d'échange de clé
(forward secrecy confirmée) — cohérent avec les suites configurées. Pour
observer concrètement une des 6 suites `ECDHE-*` de `ssl_ciphers` plutôt
que le nom de suite TLS 1.3 (différent, non listé dans `ssl_ciphers`),
forcer TLS 1.2 côté client :

```bash
curl -sk -v --tls-max 1.2 --resolve secure-web-lab.local:443:127.0.0.1 \
  https://secure-web-lab.local/ 2>&1 | grep -i 'SSL connection'
```

### Rate limiting

```bash
for i in $(seq 1 30); do
  curl -sk -o /dev/null -w "%{http_code}\n" \
    --resolve dev.secure-web-lab.local:8443:127.0.0.1 \
    https://dev.secure-web-lab.local:8443/
done | sort | uniq -c
```

Attendu : les ~20 premières réponses en `200` (dans le burst), puis des
`429` une fois le burst épuisé pour les requêtes envoyées plus vite que
10r/s. Comme pour le test `nginx-404-flood`
([`fail2ban/README.md`](../fail2ban/README.md#tester-manuellement--ignoreself-et-pourquoi-127001-ne-suffit-pas)),
`127.0.0.1` reste une IP valide à utiliser ici : `ignoreself` est une
particularité de fail2ban, pas de `limit_req`, qui n'a aucune notion
d'IP à s'auto-exempter.

Exécuté :

```text
     23 200
      7 429
```

23 plutôt qu'exactement 20 : la boucle n'envoie pas les requêtes de façon
parfaitement instantanée (coût TLS handshake + résolution locale à chaque
itération), donc une partie du débit **soutenu** (`10r/s`) se consomme
aussi pendant le test, en plus des 20 du `burst` — comportement normal de
l'algorithme, pas un signe que le seuil est mal réglé.

### Contrôle des tailles de requêtes

```bash
# Corps de requête sous la limite (doit passer) puis au-dessus (doit être rejeté)
dd if=/dev/urandom bs=1k count=50  2>/dev/null | curl -sk -o /dev/null -w "50k  -> %{http_code}\n" \
  --resolve dev.secure-web-lab.local:8443:127.0.0.1 -X POST --data-binary @- \
  https://dev.secure-web-lab.local:8443/
dd if=/dev/urandom bs=1k count=200 2>/dev/null | curl -sk -o /dev/null -w "200k -> %{http_code}\n" \
  --resolve dev.secure-web-lab.local:8443:127.0.0.1 -X POST --data-binary @- \
  https://dev.secure-web-lab.local:8443/
```

Exécuté :

```text
50k  -> 405
200k -> 413
```

`200k -> 413` confirme la limite : rejeté avant même d'atteindre la
logique de routage, `client_max_body_size` dépassé.

`50k -> 405` (*Method Not Allowed*), pas `404` comme anticipé initialement
dans cette note — plus juste en réalité : le module de fichiers statiques
de Nginx (`ngx_http_static_module`, celui qui sert les fichiers via
`root`/`try_files`) ne traite que `GET`/`HEAD` nativement et rejette tout
autre verbe avec `405` **avant** de chercher quoi que ce soit sur disque —
il n'y a donc jamais de tentative de résolution de route pour un `POST`
sur ce site, contrairement à ce qui était supposé. Cohérent malgré tout
avec l'objectif de la vérification : le corps de 50k a bien été accepté
niveau taille (sinon on aurait eu `413` ici aussi), la requête a échoué
plus loin dans le traitement, pour une raison différente mais tout aussi
attendue sur un site purement statique.

### Timeouts

Test sur le port HTTP en clair (`8080`, dev — évite toute complication de
handshake TLS pour ce test, `client_header_timeout` s'applique de la même
façon une fois la connexion établie, TLS ou non) : envoyer une requête
volontairement incomplète, puis **attendre la réponse du serveur** sans
jamais la compléter nous-mêmes.

```bash
time timeout 20 bash -c '
  exec 3<>/dev/tcp/127.0.0.1/8080
  printf "GET / HTTP/1.1\r\nHost: dev.secure-web-lab.local\r\n" >&3
  cat <&3
'
```

**Premier essai erroné, corrigé ici** : la version initiale de ce test
insérait un `sleep 15` local entre les deux `printf`, puis mesurait le
temps total avec `time`. Erreur de méthode — `sleep 15` bloque le script
15 secondes *quoi qu'il arrive côté serveur* : que Nginx coupe la
connexion à 10s ou la laisse ouverte 60s, le `real` mesuré restait ~15s
dans les deux cas, puisque c'est notre propre attente locale qui dominait
le chrono, pas le comportement de Nginx. Le test ne mesurait donc rien
d'utile — corrigé ci-dessus en supprimant le `sleep` local et en attendant
directement la réponse du serveur via `cat`, avec un `timeout 20`
englobant pour éviter un blocage indéfini si le serveur ne coupe jamais.

Attendu maintenant : Nginx ferme la connexion après ~10s d'inactivité
(`client_header_timeout`), avant l'expiration du `timeout 20` englobant —
`real` proche de `0m10s`.

Exécuté :

```text
real    0m10.020s
user    0m0.002s
sys     0m0.005s
```

`client_header_timeout` confirmé fonctionnel : Nginx a coupé la connexion
10.02s après le dernier octet reçu, sans attendre le `timeout 20`
englobant.

### Protection contre divulgation de version

Nécessite d'avoir redéployé **et** le contenu (`error.html` est un nouveau
fichier dans `app/static-site/`) **et** la config (`custom-error-pages.conf`
est un nouveau snippet inclus dans les 3 vhosts) :

```bash
./scripts/deploy-static-site.sh dev
./scripts/deploy-nginx-config.sh dev
```

```bash
curl -sk --resolve dev.secure-web-lab.local:8443:127.0.0.1 \
  https://dev.secure-web-lab.local:8443/inexistant
```

Attendu : le contenu de `error.html` (« Une erreur est survenue »), pas la
page par défaut de Nginx — et toujours un code `404` réel
(`curl -o /dev/null -w "%{http_code}"` pour le vérifier séparément du
corps).

Exécuté :

```text
<!DOCTYPE html>
<html lang="fr">
...
  <h1>Une erreur est survenue</h1>
  <p>La requête n'a pas pu être traitée. Réessayez plus tard.</p>
...
```

Page personnalisée confirmée servie à la place de la page par défaut de
Nginx, code HTTP réel toujours `404` :

```bash
curl -sk -o /dev/null -w "%{http_code}\n" --resolve dev.secure-web-lab.local:8443:127.0.0.1 \
  https://dev.secure-web-lab.local:8443/inexistant
```
```text
404
```

### Journalisation avancée

Nouveau fichier `conf.d/` : redéployer la config avant de tester.

```bash
./scripts/deploy-nginx-config.sh dev
```

```bash
curl -sk -D - -o /dev/null --resolve dev.secure-web-lab.local:8443:127.0.0.1 \
  https://dev.secure-web-lab.local:8443/ | grep -i x-request-id

sudo tail -1 /var/log/nginx/secure-web-lab-dev.access.log
```

Attendu : le même identifiant apparaît dans le header `X-Request-Id` de la
réponse **et** dans le champ `req_id=` de la dernière ligne du log
d'accès — avec `rt=` et `ssl="TLSv1.3/TLS_AES_..."` (ou suite TLS 1.2 si
forcé) renseignés.

Pour vérifier le point de sévérité `limit_req_log_level`/`error_log` :
déclencher un rejet 429 (voir
[test rate limiting](#rate-limiting-1) plus haut), puis :

```bash
sudo tail -5 /var/log/nginx/secure-web-lab-dev.error.log
```

Attendu : une ligne `[warn]` mentionnant `limiting requests`, présente
grâce au `error_log ... warn;` explicite — absente si l'un des deux
réglages avait été omis.

*(sortie réelle à ajouter ici après exécution)*
