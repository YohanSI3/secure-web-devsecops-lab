# Séparation des secrets : applicatif, infrastructure, CI

## Le principe : trois magasins, pas un coffre unique

Une tentation naturelle, surtout sur un petit projet, est de tout mettre
au même endroit : un seul outil, un seul accès, une seule chose à retenir.
Pour les secrets précisément, c'est l'inverse qui protège le mieux — les
isoler par **catégorie d'usage**, pas par commodité de gestion. La raison
tient au **rayon d'explosion** (*blast radius*) d'une fuite : si un seul
magasin contient à la fois les secrets applicatifs, les secrets
d'infrastructure et les secrets de CI, compromettre n'importe lequel des
trois donne accès aux trois. Les séparer fait qu'une fuite dans un
contexte reste contenue à ce contexte.

## Les trois catégories, et pourquoi elles diffèrent vraiment

- **Secrets applicatifs** — ce dont l'application a besoin pour
  fonctionner en production (identifiants de base de données, clé de
  signature de session, clé API d'un service tiers appelé à l'exécution).
  Lus par le **process applicatif lui-même**, à l'exécution.
- **Secrets d'infrastructure** — ce qui sert à **administrer** les
  systèmes qui font tourner l'application, jamais lu par l'application
  elle-même (identifiants superuser d'une base de données, clés de
  descellement d'un coffre, jeton racine). Utilisés par un **opérateur
  humain**, ponctuellement.
- **Secrets de CI** — ce dont le pipeline d'intégration continue a besoin
  pour construire/tester/déployer (jeton pour publier un artefact,
  identifiants pour un déploiement automatisé). Lus par le **runner CI**,
  pendant l'exécution d'un workflow, jamais par l'application elle-même
  ni par un humain directement.

Trois audiences différentes (process applicatif, opérateur humain, runner
CI), trois moments différents (exécution continue, intervention
ponctuelle, exécution d'un pipeline) — mélanger ces magasins revient à
donner à chaque audience un accès dont elle n'a par ailleurs aucun besoin.
Un pipeline CI compromis (dépendance malveillante dans une action
tierce, par exemple — risque réel, pas théorique) ne doit jamais pouvoir,
par ce biais, lire un secret applicatif de production : si c'est
possible, c'est que la séparation n'existe pas vraiment, seulement des
noms de dossiers différents pour le même accès.

## Le test simple pour vérifier une séparation réelle

Se demander, pour chaque secret : *qui a besoin de le lire pour faire son
travail, et seulement ça ?* Si la réponse implique plusieurs audiences
("le pipeline CI *et* l'application en lisent la même valeur"), c'est un
signal qu'une étape manque — soit deux secrets distincts devraient exister
là où un seul fait actuellement double emploi, soit l'un des deux accès
n'est pas réellement nécessaire et devrait être retiré.

Voir [`.github/README.md#séparation-secret-applicatif--infra--ci`](../../.github/README.md#séparation-secret-applicatif--infra--ci)
pour la classification concrète appliquée à ce projet.
