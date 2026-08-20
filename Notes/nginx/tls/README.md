# TLS local

## Contexte

Suite de la Phase 1 du `ToDo.md` : "TLS local ou lab". Chaque environnement
(dev, staging, prod-lab) sert désormais son contenu en HTTPS, avec
redirection automatique depuis HTTP, en utilisant une CA locale créée pour
ce lab plutôt que des certificats publics (aucun nom de domaine public à
ce stade).

Détail réparti dans des fichiers séparés :

- [`local-ca-et-chaine-de-confiance.md`](local-ca-et-chaine-de-confiance.md)
  — ce qu'est une CA, pourquoi en créer une localement, chaîne de
  confiance, ce que ça implique par rapport à un certificat public.
- [`certificats-serveur-et-san.md`](certificats-serveur-et-san.md) —
  génération des certificats par environnement, rôle du SAN, durée de
  validité choisie.
- [`deploiement-et-permissions.md`](deploiement-et-permissions.md) —
  où et comment les clés/certificats sont déployés, modèle de permissions,
  différence avec le webroot.
- [`protocoles-tls-heritage-et-fusion.md`](protocoles-tls-heritage-et-fusion.md)
  — piège rencontré : `ssl_protocols` fusionne au lieu de remplacer entre
  deux déclarations au même niveau, et comment ça a été corrigé.

## Ce qui a été fait

- Scripts (dans l'ordre d'exécution) :
  1. [`scripts/generate-local-ca.sh`](../../../scripts/generate-local-ca.sh)
     — crée la CA locale dans `.tls/ca/` (une seule fois, idempotent).
  2. [`scripts/generate-server-cert.sh`](../../../scripts/generate-server-cert.sh)
     `<env>` — génère clé + certificat serveur signés par la CA, dans
     `.tls/<env>/`.
  3. [`scripts/deploy-tls-cert.sh`](../../../scripts/deploy-tls-cert.sh)
     `<env>` — copie le résultat vers `/etc/nginx/ssl/<env>/`.
  4. [`scripts/setup-tls.sh`](../../../scripts/setup-tls.sh) — enchaîne les
     trois étapes précédentes pour les trois environnements.
- `.tls/` ajouté à [`.gitignore`](../../../.gitignore) : la CA et les clés
  privées ne sont **jamais** commitées, uniquement régénérées localement.
- Config nginx par environnement : bloc HTTP qui redirige (301) vers HTTPS,
  bloc HTTPS avec `ssl_certificate`/`ssl_certificate_key`.
- `ssl_protocols TLSv1.2 TLSv1.3;` appliqué via
  [`nginx/snippets/tls-hardening.conf`](../../../nginx/snippets/tls-hardening.conf)
  (inclus dans chaque server block HTTPS — pas dans `conf.d/`, voir
  `protocoles-tls-heritage-et-fusion.md` pour le piège rencontré).

```bash
./scripts/setup-tls.sh
./scripts/deploy-all-environments.sh
```

## Vérification

`curl` seul (sans `--cacert`) rejette un certificat signé par une CA qu'il
ne connaît pas — comportement voulu et attendu, à ne pas contourner avec
`-k` (qui désactiverait toute vérification, y compris de nom d'hôte).
`--resolve` permet de tester avec le bon nom d'hôte (nécessaire pour le
SNI, voir `certificats-serveur-et-san.md`) sans toucher `/etc/hosts` :

```bash
curl -v --cacert .tls/ca/ca.crt \
  --resolve dev.secure-web-lab.local:8443:127.0.0.1 \
  https://dev.secure-web-lab.local:8443/
# doit afficher "SSL certificate verify ok"

curl -sI --resolve dev.secure-web-lab.local:8080:127.0.0.1 \
  http://dev.secure-web-lab.local:8080/
# doit répondre 301 vers https://dev.secure-web-lab.local:8443/
```

Répéter pour `staging` (port 8081/8444) et `prod` (port 80/443, sans
suffixe de port dans l'URL de redirection).

## Prochaines étapes

- Phase 1 : headers de sécurité de base (voir
  [`Notes/nginx/headers-securite/`](../headers-securite/README.md), fait
  dans la foulée).
- Phase 2 : durcissement TLS plus poussé (suites de chiffrement précises,
  HSTS preload le cas échéant, OCSP stapling, session resumption).
