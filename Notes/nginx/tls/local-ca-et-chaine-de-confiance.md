# CA locale et chaîne de confiance

## Le problème que TLS résout

HTTPS repose sur deux garanties distinctes apportées par TLS : le trafic
est chiffré (confidentialité) **et** le client a la preuve qu'il parle
bien au bon serveur (authentification), pas à un attaquant interposé
(attaque de type "man-in-the-middle"). La deuxième garantie repose
entièrement sur les certificats et la chaîne de confiance — le chiffrement
seul ne suffit pas : un attaquant peut tout aussi bien chiffrer sa propre
connexion frauduleuse.

## Qu'est-ce qu'une CA (Certificate Authority)

Une CA est une entité qui signe des certificats pour attester qu'une clé
publique donnée appartient bien à un domaine donné. Un client (navigateur,
`curl`) fait confiance à un certificat serveur uniquement s'il peut
remonter la chaîne de signatures jusqu'à une CA qu'il connaît et accepte
déjà (une CA "racine de confiance", généralement pré-installée dans le
système d'exploitation ou le navigateur).

En usage public (un vrai nom de domaine exposé sur Internet), cette CA est
un tiers reconnu (ex. Let's Encrypt, DigiCert...) dont la clé racine est
déjà présente dans le magasin de confiance de tous les systèmes/navigateurs
standards. Aucun domaine public n'existe pour ce lab (`*.secure-web-lab.local`
n'est enregistré nulle part) : aucune CA publique n'accepterait de signer
un certificat pour ce nom.

## Pourquoi une CA locale plutôt qu'un certificat auto-signé "nu"

Deux approches étaient possibles :

1. **Certificat auto-signé directement** — le certificat serveur se signe
   lui-même (`CA` = lui-même). Fonctionne pour chiffrer, mais chaque client
   qui s'y connecte doit explicitement ignorer ou accepter individuellement
   ce certificat précis (pas de chaîne de confiance à vérifier).
2. **CA locale intermédiaire** (choix retenu) — une seule paire
   clé/certificat "CA" est créée une fois (`.tls/ca/`), qui signe ensuite
   les certificats de chaque environnement. Un client qui fait confiance à
   cette CA locale (via `--cacert` pour `curl`, ou en l'important
   dans un magasin de certificats système/navigateur) fait alors
   automatiquement confiance à **tous** les certificats qu'elle signe,
   présents et futurs, sans reconfiguration à chaque nouveau certificat.

Le choix d'une CA locale reproduit fidèlement le fonctionnement d'une vraie
PKI (Public Key Infrastructure) à échelle réduite : une racine de confiance
unique, des certificats "feuille" (serveur) émis à partir d'elle. C'est ce
qui permet de comprendre la mécanique de validation réellement utilisée en
production, plutôt qu'un raccourci pédagogiquement plus pauvre.

## Statut de cette CA

La CA locale (`.tls/ca/ca.key` + `ca.crt`) n'est connue **que** de ce lab :
elle n'est installée dans aucun magasin de confiance système par défaut.
Un `curl` sans `--cacert .tls/ca/ca.crt` explicite rejettera donc la
connexion (erreur `SSL certificate problem: unable to get local issuer
certificate`) — comportement attendu, pas un bug. Importer cette CA dans un
magasin de confiance système ou navigateur (pour naviguer sans avertissement
depuis un vrai navigateur) est une étape volontairement laissée de côté ici
(hors scope Phase 1, et une CA locale importée dans le magasin système
mérite d'être traitée avec la même prudence qu'un vrai secret : elle
pourrait, si compromise, signer des certificats acceptés par la machine
pour n'importe quel domaine).

## Pourquoi cette clé ne doit jamais être commitée

`.tls/ca/ca.key` est la pièce la plus sensible de tout ce dispositif :
quiconque la possède peut émettre un certificat accepté par tout client
faisant confiance à cette CA, pour n'importe quel nom de domaine. D'où :

- génération exclusivement locale, jamais partagée ni transmise,
- `chmod 600` appliqué immédiatement après génération,
- `.tls/` dans `.gitignore` dès sa création — avant même le premier
  `openssl genrsa`, pour ne jamais risquer un commit accidentel.

Prépare directement l'état d'esprit de la Phase 4 du `ToDo.md` (secrets
management) : une clé privée est un secret, elle se génère et se déploie,
elle ne se versionne jamais.
