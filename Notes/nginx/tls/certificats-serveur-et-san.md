# Certificats serveur : SAN, CSR, durée de validité

Référence : [`scripts/generate-server-cert.sh`](../../../scripts/generate-server-cert.sh)

## Étapes de génération

1. **Clé privée** (`server.key`) — `openssl genrsa ... 2048`. Propre à
   chaque environnement, jamais partagée entre `dev`/`staging`/`prod`, pour
   que la compromission d'un environnement n'affecte pas les autres.
2. **CSR** (Certificate Signing Request, `server.csr`) — une demande de
   signature contenant la clé publique correspondante et l'identité
   demandée (`CN=<domaine>`). Le CSR ne contient jamais la clé privée.
3. **Signature par la CA locale** (`server.crt`) — la CA (voir
   [`local-ca-et-chaine-de-confiance.md`](local-ca-et-chaine-de-confiance.md))
   signe le CSR et produit le certificat final.

## SAN (Subject Alternative Name)

Le certificat inclut une extension `subjectAltName = DNS:<domaine>`, en
plus du `CN` (Common Name) présent dans le CSR. Les clients TLS modernes
(navigateurs, `curl` récent) ignorent le `CN` pour la validation du nom
d'hôte et ne se fient **qu'au SAN** — un certificat sans SAN correspondant
est rejeté même si son `CN` correspond exactement au nom demandé. D'où la
génération systématique d'un fichier d'extension (`server.ext`) contenant
le SAN, passé à `openssl x509 -req ... -extfile server.ext` : sans cette
étape, le certificat généré ne serait plus accepté par les outils actuels.

## SNI (Server Name Indication) — pourquoi `curl --resolve` et pas juste `-H Host`

Sur un déploiement en HTTPS, le nom d'hôte demandé doit être connu **avant**
même que la requête HTTP ne soit envoyée : c'est le rôle du SNI, une
extension de la négociation TLS où le client annonce le nom d'hôte visé dès
le handshake, avant que le chiffrement ne soit établi. C'est ce qui permet
à nginx de choisir le bon certificat (et le bon `server_name`) quand
plusieurs sites partagent une même adresse/port.

Une requête `curl -H "Host: ..."` seule ne suffit donc pas en HTTPS : le
header `Host` n'intervient qu'une fois la connexion TLS déjà établie, donc
après que le SNI a déjà déterminé quel certificat a été présenté. Utiliser
`curl --resolve <domaine>:<port>:127.0.0.1` fait correspondre le nom
d'hôte réel dès la résolution DNS simulée, donc dès le SNI — sans avoir
besoin de modifier `/etc/hosts`. C'est la méthode de test employée dans
[`Notes/nginx/tls/README.md`](README.md).

## Durée de validité : 397 jours

`-days 397` dans `generate-server-cert.sh` correspond à la durée maximale
de validité qu'acceptent aujourd'hui la plupart des navigateurs modernes
pour un certificat serveur public (la limite a progressivement baissé au
fil des années — 5 ans à l'origine, puis 2 ans, puis 398 jours, poussée par
les CA/Browser Forum pour réduire la fenêtre d'exposition d'une clé
compromise ou d'informations obsolètes). Rien n'imposait cette limite ici
(la CA est privée, aucun navigateur public ne l'impose), mais aligner le
lab sur cette contrainte réelle habitue à raisonner en cycles de
renouvellement courts plutôt qu'en certificats "posés une fois pour
toutes" — pertinent pour la suite du projet (automatisation, CI, Phase 3).
