# RBAC, énumération de comptes, fixation de session

## RBAC (Role-Based Access Control)

Plutôt que de vérifier des permissions individuelles pour chaque
utilisateur ("Alice peut supprimer un article", "Bob ne peut pas"), le
RBAC regroupe les permissions par **rôle** ("admin", "user"), et
attribue un rôle à chaque utilisateur. Vérifier une autorisation revient
à vérifier le rôle courant plutôt qu'une liste de permissions par
personne — plus simple à raisonner et à auditer tant que le nombre de
rôles reste petit. Ce lab implémente le cas le plus simple (un seul champ
`role` par utilisateur, deux valeurs) ; un système plus riche
distinguerait le **rôle** (un ensemble nommé de permissions) de la
**permission** elle-même (une action précise), avec une table
d'association many-to-many — utile dès que plusieurs rôles doivent
partager certaines permissions sans toutes les partager.

## Pourquoi la même réponse pour "mauvais mot de passe" et "compte inexistant"

Un attaquant qui teste une liste d'emails contre un formulaire de
connexion cherche d'abord à savoir **lesquels existent** (l'énumération),
avant même de tenter de deviner un mot de passe — une liste d'emails
confirmés valides a de la valeur en elle-même (phishing ciblé, revente).
Si le serveur répond différemment selon "email inconnu" vs "mot de passe
incorrect" (message différent, code HTTP différent, ou même simplement un
**temps de réponse différent**), il fuit cette information même sans le
vouloir explicitement. D'où deux précautions combinées dans ce lab (voir
[`app/backend/README.md`](../../app/backend/README.md#résistance-à-lénumération-de-comptes)) :
un message et un code HTTP strictement identiques dans les deux cas, et
un coût de calcul (hachage bcrypt) similaire même quand l'email n'existe
pas, pour ne pas laisser un temps de réponse plus court trahir l'absence
du compte.

## Fixation de session

Une attaque par fixation de session force la victime à utiliser un
identifiant de session **choisi par l'attaquant** (par exemple via un
lien piégé qui pose déjà un cookie de session avant la connexion). Si le
serveur ne change pas cet identifiant au moment où la victime
s'authentifie, l'attaquant — qui connaît déjà cet identifiant depuis le
début — récupère une session pleinement authentifiée dès que la victime
se connecte, sans jamais avoir eu besoin du mot de passe. La parade :
**régénérer** l'identifiant de session au moment précis de
l'authentification (`req.session.regenerate()`), pour qu'un identifiant
connu avant connexion ne soit jamais celui qui devient valide après.
