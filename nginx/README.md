# Nginx — documentation technique

Choix d'implémentation concrets pour la configuration Nginx de ce lab. Pour
le fonctionnement général des concepts TLS/HTTP sous-jacents, voir
[`Notes/nginx/`](../Notes/nginx/README.md) (TLS, headers, environnements,
utilisateur dédié).

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

```bash
curl -sk -v --resolve secure-web-lab.local:443:127.0.0.1 \
  https://secure-web-lab.local/ 2>&1 | grep -iE 'SSL connection|Cipher|strict-transport'
```

Attendu : une suite `ECDHE-*-GCM-*` ou `ECDHE-*-CHACHA20-*` (TLS 1.2) ou
`TLS_AES_*`/`TLS_CHACHA20_*` (TLS 1.3 — nom de suite différent car négocié
indépendamment de `ssl_ciphers`), et le header HSTS se terminant par
`; preload`.

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
