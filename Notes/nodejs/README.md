# Node.js

## Contexte

Phase 5 du `ToDo.md` (IAM) : le lab passe d'un site purement statique à
une vraie application, nécessitant un runtime pour exécuter du code
serveur. Cours général sur Node.js/npm ; les choix concrets (paquets
retenus, structure du backend) sont dans
[`app/backend/README.md`](../../app/backend/README.md).

## Pourquoi un dépôt tiers (NodeSource) alors que Nginx utilise le dépôt Ubuntu officiel

Point de tension assumé avec le principe déjà appliqué à Nginx
(« dépôts officiels Ubuntu uniquement, pas de PPA tiers », voir
[`Notes/nginx/installation/README.md`](../nginx/installation/README.md)) :
le paquet `nodejs` livré dans les dépôts Ubuntu 24.04 est une version
figée au moment de la sortie de la distribution (généralement déjà
ancienne, parfois en fin de support au moment où on l'installe des mois/
années plus tard). Un projet backend actif a besoin d'une version de
Node.js elle-même maintenue (correctifs de sécurité réguliers) — ce que
le dépôt Ubuntu ne peut pas garantir pour un runtime qui évolue à un
rythme bien plus rapide que le cycle de release d'une distribution LTS.

[NodeSource](https://github.com/nodesource/distributions) n'est pas un
PPA communautaire non maîtrisé : c'est le canal de distribution APT
**officiellement recommandé par le projet Node.js lui-même** pour les
systèmes basés sur Debian/Ubuntu, documenté sur nodejs.org. La distinction
qui justifie l'exception : la confiance se place dans la source amont
(le projet Node.js) plutôt que dans le mainteneur de la distribution —
même logique de confiance que pour les dépôts Ubuntu, une source
différente pour une raison de cycle de vie différente entre les deux
logiciels.

## `package.json` : dépendances, versions, verrouillage

`package.json` déclare les dépendances avec des **plages de version**
(`^7.1.0` = compatible jusqu'à la prochaine version majeure) plutôt que
des versions exactes — npm résout la version précise réellement installée
et la fige dans `package-lock.json` (généré à la première
`npm install`, à committer avec le code). Cette distinction (plage
déclarée vs version verrouillée) est ce qui permet à Dependabot
d'ouvrir des pull requests de mise à jour : il compare la version
verrouillée à ce qui existe de plus récent compatible, exactement comme
pour les actions GitHub (voir
[`.github/README.md`](../../.github/README.md#dependabot)).

## `npm audit` : SCA local, en plus de Dependabot

`npm audit` interroge la base de vulnérabilités connues de npm pour
chaque dépendance installée, directement en local — un scan SCA
(voir [`Notes/devsecops/sast-dast-sca.md`](../devsecops/sast-dast-sca.md))
qu'on peut lancer avant même de pousser du code, complémentaire aux
pull requests Dependabot qui, elles, tournent en tâche de fond sur le
dépôt. À intégrer à la CI une fois le backend stabilisé (Phase 3
approfondie, voir `ToDo.md`).
