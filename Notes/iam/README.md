# IAM — Identity and Access Management

## Contexte

Phase 5 du `ToDo.md`. IAM regroupe trois questions distinctes, souvent
confondues :

- **Identification** — qui prétend être cet utilisateur ? (un identifiant :
  email, nom d'utilisateur)
- **Authentification** — peut-il le prouver ? (un secret : mot de passe,
  MFA)
- **Autorisation** — a-t-il le droit de faire *cette* action précise ? (un
  rôle, une permission)

Les trois sont indépendantes : on peut s'identifier sans s'authentifier
(un formulaire qui demande un email sans vérifier qu'on le possède), et
être authentifié sans être autorisé à tout (un utilisateur connecté mais
pas admin). Les choix concrets pour ce lab sont dans
[`app/backend/README.md`](../../app/backend/README.md) — cette note
couvre les concepts généraux.

## Sommaire

- [`mots-de-passe.md`](mots-de-passe.md) — hachage, coût bcrypt,
  pourquoi la longueur prime sur la complexité imposée (NIST).
- [`sessions-vs-jwt.md`](sessions-vs-jwt.md) — les deux grands modèles de
  maintien d'authentification entre deux requêtes, et le compromis
  révocation vs absence d'état serveur.
- [`rbac-et-enumeration.md`](rbac-et-enumeration.md) — contrôle d'accès
  par rôle, résistance à l'énumération de comptes, fixation de session.
- [`reinitialisation-mot-de-passe.md`](reinitialisation-mot-de-passe.md) —
  jeton à usage unique, pourquoi le hacher en SHA-256 (pas bcrypt),
  pourquoi couper les sessions actives après un reset, Mailpit.

## MFA : pas dans cette phase, évolution possible

Le plan mentionne le MFA comme option, pas comme item obligatoire de la
Phase 5 — non implémenté ici. Principe pour la culture générale : un
second facteur (le plus courant, TOTP — *Time-based One-Time Password*,
un code à 6 chiffres qui change toutes les 30 secondes, dérivé d'un secret
partagé entre le serveur et une application comme Google Authenticator)
ajoute une preuve **indépendante du mot de passe** — un attaquant qui
obtiendrait le mot de passe (phishing, fuite d'une autre base réutilisée)
ne pourrait toujours pas se connecter sans ce second facteur. À
implémenter le jour où ce lab voudrait pousser l'IAM plus loin :
bibliothèque `otpauth`/`speakeasy` pour générer/vérifier les codes TOTP,
plus des codes de secours à usage unique pour le cas où l'appareil
générant les codes est perdu.
