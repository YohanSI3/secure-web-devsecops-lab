# DevSecOps

Phase 3 du `ToDo.md` — la phase du projet centrée sur la sécurité
applicative et le DevSecOps proprement dits (les phases précédentes
portaient sur le durcissement d'infrastructure). Cours général sur les
concepts et l'outillage du domaine ; les choix concrets pour ce dépôt
(quels outils, quelle CI, quelles règles) sont documentés dans
[`.github/README.md`](../../.github/README.md).

## Sommaire

- [`sast-dast-sca.md`](sast-dast-sca.md) — les grandes catégories de scan
  de sécurité (SAST, DAST, SCA, IAST), ce que chacune trouve et ne trouve
  pas, où elles s'insèrent dans un pipeline.
- [`secrets-scanning.md`](secrets-scanning.md) — comment un scanner de
  secrets détecte quelque chose (regex vs entropie), pourquoi le
  scanner *avant* commit (push protection) vaut mieux que scanner
  *après*.
- [`branches-protegees-et-ci-gate.md`](branches-protegees-et-ci-gate.md) —
  modèles de protection de branche, pourquoi une CI qui ne bloque rien
  n'est qu'un tableau de bord.
- [`paysage-outillage.md`](paysage-outillage.md) — tableau des outils
  gratuits déployés dans ce lab et de leur équivalent commercial de
  référence, pour se repérer dans ce qui se fait aujourd'hui dans
  l'industrie sans dépendre d'une licence payante ici.

## Le principe organisateur : "shift left"

Une bonne partie du vocabulaire DevSecOps tourne autour d'une seule idée :
**détecter un problème de sécurité le plus tôt possible dans le cycle de
développement**, parce que le coût de correction augmente à chaque étape
franchie sans être détecté (une faille trouvée en revue de code coûte une
relecture ; la même faille trouvée en production coûte un incident, une
communication, parfois une donnée compromise). "Shift left" désigne le
déplacement de ces contrôles vers la gauche d'une frise chronologique
classique (code → build → test → déploiement → production) :

```text
code écrit → commit → CI (PR) → merge → build → déploiement → production
   ↑              ↑         ↑                                      ↑
 éditeur/IDE   push        ici (Phase 3)                    trop tard
 (le plus tôt)  protection                                  (le plus cher
                                                              à corriger)
```

Ce dépôt implémente le niveau **CI/PR** (scans automatiques avant merge)
et une partie du niveau **push** (secret scanning natif GitHub, qui peut
bloquer un push avant même qu'il n'entre dans l'historique). Le niveau le
plus à gauche — un hook local (`pre-commit`) ou une extension d'éditeur —
n'est pas imposé ici : documenté comme geste volontaire dans
[`CONTRIBUTING.md`](../../CONTRIBUTING.md) plutôt qu'automatisé, pour ne
pas dupliquer un outillage que la CI vérifie de toute façon avant merge.
