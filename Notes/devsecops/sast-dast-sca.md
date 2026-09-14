# SAST, DAST, SCA, IAST : quatre familles de scan, pas des synonymes

Confondre ces sigles fait rater ce que chaque outil peut réellement
trouver. Les quatre partagent l'objectif (trouver une faille avant un
attaquant) mais regardent des choses complètement différentes.

## SAST — Static Application Security Testing

Analyse le **code source**, sans l'exécuter — lecture et modélisation du
flux de données (d'où vient une valeur, où elle finit) pour repérer des
motifs dangereux : injection potentielle, désérialisation non sûre, appel
crypto obsolète, secret en dur. Rapide, tourne dès qu'il y a du code
(avant même un build fonctionnel), mais **ne voit que ce qui est écrit
explicitement** — un problème de configuration à l'exécution (permissions
réelles d'un fichier sur un vrai serveur, comportement d'un vrai
certificat) lui échappe complètement.

Implémenté ici : **Semgrep OSS**
([`.github/workflows/sast.yml`](../../.github/workflows/sast.yml)),
analyse essentiellement les scripts shell de ce dépôt.

## DAST — Dynamic Application Security Testing

Analyse une **application en cours d'exécution**, de l'extérieur, comme
le ferait un attaquant réel : envoie de vraies requêtes HTTP, observe les
réponses, cherche des comportements exploitables (injection réussie, en-
tête de sécurité absent en pratique, redirection ouverte). Complémentaire
du SAST : trouve des problèmes que le code seul ne révèle pas (une
mauvaise configuration serveur, une interaction entre plusieurs
composants), mais ne voit que ce qui est atteignable par une requête —
aucune visibilité sur le code qui ne s'exécute pas dans le chemin testé.

Non implémenté dans ce dépôt à ce stade — nécessiterait une cible en
ligne (le lab tourne en local/WSL, sans exposition réseau réelle, cf.
[`Notes/ufw/reseau-wsl2-et-portee-du-filtrage.md`](../ufw/reseau-wsl2-et-portee-du-filtrage.md)).
Pertinent pour la Phase 6 du `ToDo.md` (« fuzz léger sur endpoints de
lab »), qui suppose déjà une cible qu'on choisit délibérément d'attaquer
dans un cadre maîtrisé — la nuance exacte entre DAST et un test
d'intrusion volontaire.

## SCA — Software Composition Analysis

Analyse les **dépendances tierces** (bibliothèques, paquets, images de
base) pour repérer des versions avec des vulnérabilités connues (CVE) ou
des licences incompatibles. Ne regarde pas le code qu'on a écrit
soi-même, seulement ce dont il dépend.

Implémenté ici de façon minimale : **Dependabot**
([`.github/dependabot.yml`](../../.github/dependabot.yml)), qui ne
surveille aujourd'hui que les versions des actions GitHub — seule
dépendance externe réelle du dépôt pour l'instant (pas de gestionnaire de
paquets applicatif). Le jour où une stack applicative avec dépendances
(paquets npm, pip, etc.) est ajoutée, c'est le même mécanisme qui
prendrait le relais pour elles.

## IAST — Interactive Application Security Testing

Hybride : un agent instrumente l'application **pendant qu'elle tourne**
sous des tests fonctionnels normaux (souvent en environnement de test/QA),
observant à la fois le code exécuté (comme SAST) et son comportement réel
(comme DAST). Plus précis que SAST seul (moins de faux positifs, puisqu'il
voit si un chemin de code vulnérable est réellement atteint), mais
demande une instrumentation du runtime — hors de portée d'un site
statique sans application dynamique derrière. Cité ici pour la culture du
domaine, pas retenu pour ce lab.

## Où chacun s'insère dans la CI de ce dépôt

```text
push / pull request
  ├── SAST   (sast.yml)           -- lit le code, avant tout déploiement
  ├── secrets (secrets-scan.yml)  -- lit l'historique git
  ├── lint config (nginx-lint.yml)-- proche du SAST, mais spécifique config
  └── SCA    (dependabot.yml)     -- hors CI, tourne en tâche de fond, ouvre des PR
```

Aucun DAST/IAST : demanderait une cible déployée et joignable, absente de
ce pipeline (le lab tourne en local, pas sur une infra CI accessible).
