# Durcissement TLS : suites de chiffrement, HSTS preload, OCSP, reprise de session

Suite de [`README.md`](README.md) et
[`protocoles-tls-heritage-et-fusion.md`](protocoles-tls-heritage-et-fusion.md) :
une fois les protocoles restreints à TLS 1.2/1.3, quatre réglages plus fins
restaient à comprendre. Les choix concrets pour ce lab sont dans
[`nginx/README.md`](../../../nginx/README.md) — cette note couvre le
fonctionnement général.

## Suite de chiffrement (cipher suite)

Une **suite de chiffrement** combine plusieurs algorithmes négociés
ensemble pour une connexion TLS :

- **échange de clé** — comment client et serveur s'accordent sur une clé
  de session sans la transmettre en clair (ex. ECDHE) ;
- **authentification** — comment le client vérifie l'identité du serveur
  (la clé du certificat : RSA ou ECDSA) ;
- **chiffrement symétrique** — l'algorithme qui protège les données une
  fois la clé de session établie (ex. AES-256-GCM) ;
- **intégrité** — comment détecter une altération des données (les modes
  **AEAD** — *Authenticated Encryption with Associated Data*, ex. GCM,
  ChaCha20-Poly1305 — combinent chiffrement et intégrité en un seul
  mécanisme, plus sûr qu'un MAC calculé séparément).

En **TLS 1.2**, cette combinaison se choisit explicitement via
`ssl_ciphers` (une liste ordonnée de suites acceptées). En **TLS 1.3**, la
norme a supprimé toute suite jugée risquée dès sa conception : seul
(EC)DHE est permis comme échange de clé (plus d'échange de clé RSA
statique), et seuls des modes AEAD sont permis pour le chiffrement — la
suite se réduit donc à choisir l'algorithme symétrique, non configurable
via `ssl_ciphers` (nginx/OpenSSL gèrent ça séparément).

## Pourquoi exclure certaines suites plutôt que tout accepter

- **RSA comme échange de clé (pas d'ECDHE/DHE)** — la même clé privée sert
  à la fois à authentifier le serveur et à établir la clé de session : si
  cette clé privée est un jour compromise, **tout le trafic déjà capturé
  dans le passé** redevient déchiffrable rétroactivement. Sans **forward
  secrecy** (propriété apportée par (EC)DHE : une clé de session éphémère,
  différente à chaque connexion, jamais dérivable de la clé privée du
  certificat), une compromission future répare le passé pour l'attaquant
  qui aurait enregistré le trafic chiffré à l'avance.
- **CBC (mode de chiffrement par bloc)** — historiquement touché par
  plusieurs attaques par *padding oracle* (BEAST, Lucky13) exploitant des
  détails d'implémentation du mode CBC lui-même, pas une faiblesse de
  l'algorithme de chiffrement sous-jacent.
- **RC4** — algorithme de flux dont les biais statistiques permettent, avec
  assez de trafic observé, de retrouver des fragments de texte en clair.
- **3DES** — taille de bloc de 64 bits jugée trop petite pour le volume de
  trafic chiffré moderne (attaque *Sweet32*, collision de bloc).

## HSTS preload

Un header `Strict-Transport-Security` classique a une limite structurelle
: le navigateur ne le connaît qu'**après une première visite HTTPS
réussie** — la toute première requête vers un domaine peut donc encore
partir en clair (HTTP), le temps que la redirection vers HTTPS s'exécute,
laissant une fenêtre pour une attaque par interception (*SSL stripping*).

La **liste de préchargement HSTS** (HSTS preload list) répond à ce
problème autrement : une liste de domaines codée en dur, distribuée avec
le code source de Chromium et reprise par la plupart des navigateurs
majeurs, qui applique HTTPS-only **dès la toute première connexion**,
avant même d'avoir jamais vu de header HSTS pour ce domaine. L'inscription
se fait volontairement sur https://hstspreload.org, après vérification de
critères précis (rediriger tout HTTP vers HTTPS, servir le header HSTS
avec au minimum `max-age=31536000` (1 an), `includeSubDomains`, et
`preload` sur le domaine lui-même).

**Risque particulier, à retenir avant d'appliquer `preload` sur un vrai
domaine** : l'inscription est quasiment un aller simple. Le retrait d'un
domaine de la liste met plusieurs mois à se propager, puisqu'il est
distribué avec les cycles de version des navigateurs, pas en temps réel —
un domaine inscrit qui perdrait ensuite la capacité de servir du HTTPS
correctement (certificat expiré, migration d'hébergeur ratée) resterait
inaccessible en HTTP pour une bonne partie de ses visiteurs pendant toute
cette période. D'où l'usage courant de tester `max-age`/`includeSubDomains`
en conditions réelles pendant plusieurs semaines avant d'ajouter `preload`
et de soumettre.

## Révocation de certificat, OCSP, et stapling

Un certificat peut devenir invalide **avant sa date d'expiration** (clé
privée compromise, certificat émis par erreur) — la CA doit alors pouvoir
communiquer cette révocation. Deux mécanismes historiques :

- **CRL** (*Certificate Revocation List*) — une liste complète, publiée
  périodiquement par la CA, de tous les certificats révoqués. Le client
  doit la télécharger (potentiellement volumineuse) et la garder à jour.
- **OCSP** (*Online Certificate Status Protocol*) — le client interroge en
  direct un serveur de la CA (le **répondeur OCSP**, dont l'URL est
  embarquée dans le certificat) : « ce certificat précis est-il toujours
  valide ? ». Plus léger que télécharger une CRL entière, mais avec deux
  défauts : un aller-retour réseau supplémentaire à chaque connexion (donc
  plus lent), et la CA apprend, à chaque requête OCSP, quel client visite
  quel site (fuite de confidentialité, la CA devient un tiers qui observe
  les habitudes de navigation).

**OCSP stapling** corrige les deux défauts : c'est le **serveur** (Nginx
ici) qui interroge périodiquement le répondeur OCSP à l'avance, obtient
une réponse **signée par la CA** attestant la validité du certificat à un
instant donné, et l'attache (« agrafe », *staple*) directement à la
poignée de main TLS avec le client. Le client n'a plus besoin de contacter
la CA lui-même : il reçoit une preuve de validité déjà signée, avec sa
propre certification cryptographique, en même temps que le certificat.
Bénéfice double : pas de round-trip client→CA (latence), et la CA
n'apprend plus qui visite quel site (seul le serveur l'interroge, à son
propre rythme, pas à chaque visiteur).

Prérequis structurel, absent de ce lab : **il faut une CA qui exploite
réellement un répondeur OCSP** — un serveur qui répond à ces requêtes.
Une CA locale auto-signée, créée uniquement pour ce lab, n'en fait
tourner aucun ; il n'y a donc littéralement rien à agrafer.

## Reprise de session (session resumption)

Une poignée de main TLS complète est coûteuse : génération de clés
éphémères, opérations de cryptographie asymétrique, plusieurs
allers-retours réseau avant le premier octet de données applicatives. La
**reprise de session** évite de repayer ce coût à chaque nouvelle
connexion d'un même client, via deux mécanismes :

- **Cache de session** (`ssl_session_cache`) — le serveur garde en mémoire
  l'état de la session (identifié par un ID de session), et peut la
  reprendre directement si le client revient avec cet ID. Nécessite un
  stockage côté serveur (mémoire), partagé entre workers pour être utile
  dans un serveur multi-process comme Nginx.
- **Tickets de session** (`ssl_session_tickets`) — approche sans état côté
  serveur : le serveur chiffre l'état de la session dans un « ticket »
  remis au client, qui le represente à la reconnexion. Le serveur n'a rien
  à stocker (utile pour répartir la charge sur plusieurs machines sans
  synchroniser un cache), mais la sécurité du mécanisme repose entièrement
  sur la clé qui chiffre ces tickets : une clé non tournée régulièrement,
  si elle fuit ou reste en usage trop longtemps, permet de déchiffrer
  rétroactivement toutes les sessions dont un ticket aurait été intercepté
  et conservé — un contournement indirect de la forward secrecy pourtant
  obtenue par ailleurs via ECDHE. C'est ce compromis qui justifie de
  désactiver les tickets par défaut tant qu'aucune rotation de clé n'est
  mise en place.
