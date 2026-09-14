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
