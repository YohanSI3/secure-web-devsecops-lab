# Nginx — documentation technique

Choix d'implémentation concrets pour la configuration Nginx de ce lab. Pour
le fonctionnement général des concepts TLS/HTTP sous-jacents, voir
[`Notes/nginx/`](../Notes/nginx/README.md) (TLS, headers, environnements,
utilisateur dédié).

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

Ces réglages vivent dans `snippets/`, déjà reliés à `/etc/nginx/` par
[`scripts/deploy-nginx-config.sh`](../scripts/deploy-nginx-config.sh) — pas
de nouveau script nécessaire, un simple reload suffit après avoir tiré les
changements :

```bash
sudo nginx -t
sudo systemctl reload nginx
```

## Vérification

```bash
curl -sk -v --resolve secure-web-lab.local:443:127.0.0.1 \
  https://secure-web-lab.local/ 2>&1 | grep -iE 'SSL connection|Cipher|strict-transport'
```

Attendu : une suite `ECDHE-*-GCM-*` ou `ECDHE-*-CHACHA20-*` (TLS 1.2) ou
`TLS_AES_*`/`TLS_CHACHA20_*` (TLS 1.3 — nom de suite différent car négocié
indépendamment de `ssl_ciphers`), et le header HSTS se terminant par
`; preload`.

*(sortie réelle à ajouter ici après exécution)*
