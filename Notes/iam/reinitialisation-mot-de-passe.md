# Réinitialisation de mot de passe

## Contexte

Dernier point obligatoire de la Phase 5 (IAM) du `ToDo.md` — le MFA reste
volontairement en évolution future (marqué "option" dans le plan, voir
[`app/backend/README.md`](../../app/backend/README.md)). Les choix
concrets sont documentés dans
[`app/backend/README.md`](../../app/backend/README.md) — cette note
couvre les concepts.

## Pourquoi un jeton à usage unique plutôt que rouvrir une session

Le mécanisme ne redemande jamais le mot de passe actuel (par définition,
l'utilisateur l'a oublié) : la preuve d'identité devient **la possession
de la boîte mail** associée au compte, via un jeton envoyé uniquement à
cette adresse. Ce jeton doit donc avoir des propriétés différentes d'un
mot de passe :

- **à usage unique** (`used_at`, colonne dédiée) — une fois consommé, il
  ne doit plus jamais fonctionner, même s'il fuit ensuite (log, historique
  navigateur).
- **de courte durée de vie** (30 minutes ici) — réduit la fenêtre
  d'exploitation si l'email est intercepté après coup.
- **à haute entropie générée par la machine** (`crypto.randomBytes(32)`,
  256 bits) plutôt que choisi par un humain — contrairement à un mot de
  passe, il n'a pas besoin d'être mémorisable, donc aucune raison de
  limiter son entropie.

## Pourquoi hacher le jeton en base (et pourquoi SHA-256, pas bcrypt)

Même logique que pour un mot de passe (voir
[`mots-de-passe.md`](mots-de-passe.md)) : ne jamais stocker en clair une
valeur qui accorde un accès. Si la base fuit, un attaquant avec les
`token_hash` ne peut pas les réutiliser directement pour réinitialiser un
mot de passe à la place de l'utilisateur légitime — il faudrait qu'il
possède le jeton d'origine, jamais stocké nulle part en clair après son
envoi par email.

Contrairement au mot de passe, ce hash utilise **SHA-256** plutôt que
bcrypt. La lenteur volontaire de bcrypt sert à ralentir le brute-force
d'un secret à **faible entropie choisi par un humain** (un mot de passe
mémorisable a un espace de possibilités bien plus restreint qu'il n'y
paraît). Le jeton de reset est déjà 256 bits d'aléa cryptographique :
même sans ralentissement volontaire, le deviner par force brute est déjà
hors de portée. Appliquer bcrypt ici ajouterait un coût de calcul à
chaque tentative de reset sans bénéfice de sécurité supplémentaire.

## Pourquoi couper toutes les sessions actives après un reset réussi

Un reset de mot de passe est souvent déclenché parce que le compte est
**déjà compromis** (mot de passe deviné, réutilisé ailleurs et fuité) —
l'attaquant a pu, avant que la victime ne réagisse, ouvrir sa propre
session avec l'ancien mot de passe. Changer le mot de passe seul
n'invaliderait pas cette session déjà active : elle continuerait de
fonctionner tant que son cookie reste valide, puisqu'une session (voir
[`sessions-vs-jwt.md`](sessions-vs-jwt.md)) ne revérifie pas le mot de
passe à chaque requête. Supprimer toutes les lignes de session
associées au compte au moment du reset force *tout le monde*, y compris
un attaquant déjà connecté, à se réauthentifier avec le nouveau mot de
passe — un bénéfice direct du choix "sessions côté serveur" plutôt que
JWT : l'effet est immédiat, sans attendre l'expiration de quoi que ce
soit.

## Pourquoi Mailpit plutôt qu'un vrai envoi d'email

Ce lab ne doit jamais envoyer de vrai email (pas de fournisseur, pas de
domaine public légitime pour ça). Deux options pour tester quand même le
flux de bout en bout : renvoyer le jeton directement dans la réponse API
(le plus simple, mais un raccourci qui ne existerait dans aucune
application réelle — fuite immédiate du secret à quiconque intercepte la
réponse), ou faire tourner un **serveur SMTP local qui capture les
emails sans les envoyer** (Mailpit) — pratique standard des équipes de
développement pour tester un flux d'email réaliste sans jamais risquer
d'envoyer quoi que ce soit à une vraie adresse. Voir
[`app/backend/README.md`](../../app/backend/README.md) pour le
déploiement concret, et
[`Notes/devsecops/paysage-outillage.md`](../devsecops/paysage-outillage.md)
pour les fournisseurs réels (payants) que Mailpit remplace ici.
