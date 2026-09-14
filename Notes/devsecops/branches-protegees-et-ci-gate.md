# Branches protégées : la CI comme porte, pas comme tableau de bord

## Le piège d'une CI "informative"

Une CI qui tourne sur chaque push, affiche un ✅/❌, mais que rien
n'empêche d'ignorer avant de merger, n'est qu'un indicateur — utile pour
regarder, sans effet si personne ne regarde. La **protection de branche**
transforme cet indicateur en condition bloquante : GitHub refuse
littéralement le bouton "Merge" tant que les checks requis ne sont pas
verts. C'est ce changement, pas l'existence de la CI elle-même, qui fait
qu'un scan de sécurité *empêche* réellement un problème d'atteindre
`main`, plutôt que de simplement le signaler après coup.

## Required reviewers : le compromis d'un dépôt solo

La plupart des guides de protection de branche recommandent d'exiger
l'approbation d'au moins une autre personne avant de merger — un
deuxième regard humain attrape des choses qu'aucun outil automatisé ne
détecte (une intention métier incorrecte, un choix architectural
discutable). Sur un dépôt à un seul contributeur, cette règle est
inapplicable telle quelle : l'exiger bloquerait indéfiniment toute PR,
personne d'autre n'existant pour approuver.

Choix retenu pour ce lab (voir
[`.github/README.md`](../../.github/README.md#branches-protégées)) :
`Require approvals` à 0, et report de toute la charge de "porte de
qualité" sur les checks automatisés (CI) plutôt que sur une revue humaine
absente par construction. Ce n'est **pas** l'équivalent d'une vraie revue
de code — un outil ne juge pas la pertinence d'une décision, seulement des
critères qu'on lui a appris à vérifier — mais reste strictement mieux que
l'absence totale de porte (poussée directe sur `main`, sans passage par
PR ni check).

## Linear history et squash merge

Un `git merge` classique crée un commit de fusion qui préserve la
structure exacte de la branche (tous les commits intermédiaires, y
compris les "wip", "fix typo", etc.) — utile pour une investigation
archéologique fine, mais rend l'historique de `main` difficile à
parcourir d'un coup d'œil. Le **squash merge** réduit toute une PR à un
seul commit sur `main`, résumant le changement dans son ensemble — cohérent
avec le principe déjà appliqué dans les `Notes/` de ce dépôt (documenter
le *pourquoi*, pas accumuler un historique brut de tâtonnements). `Require
linear history` interdit les commits de fusion classiques, imposant de
fait le squash (ou le rebase) comme seule méthode de merge acceptée.

## "Do not allow bypassing" — se protéger soi-même autant que les autres

Une protection de branche configurable pour être contournée par les
administrateurs du dépôt ne protège que les autres contributeurs, jamais
le mainteneur lui-même au moment où il serait le plus tenté de la
contourner ("juste cette fois, c'est urgent"). Cocher l'option qui
applique la règle même aux administrateurs transforme la protection en
véritable politique plutôt qu'en simple recommandation avec échappatoire —
directement analogue au choix déjà fait ailleurs dans ce lab de ne pas se
laisser d'exception "juste au cas où" (ex. ne pas ouvrir un port par
commodité, voir
[`firewall/README.md`](../../firewall/README.md#délibérément-non-ouvert--ssh-22tcp)).
