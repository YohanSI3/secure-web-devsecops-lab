# Instructions pour Claude Code — secure-web-devsecops-lab

## Documentation : deux types, jamais mélangés

Pour **chaque** implémentation réalisée dans ce projet, produire
systématiquement les deux types de documentation suivants :

1. **`Notes/<sujet>/`** — contenu conceptuel / pédagogique ("cours") :
   explique le fonctionnement général d'une technologie ou d'un concept,
   indépendamment des choix précis faits dans ce dépôt. Jamais de détail
   d'implémentation spécifique à ce projet ici.
2. **Documentation technique co-localisée avec l'artefact réel** (ex.
   `nginx/README.md`, `firewall/README.md`, `postgresql/README.md`,
   `vault/README.md`, `app/backend/README.md`, `.github/README.md`) —
   **jamais** dans `Notes/`. Explique en détail ce qui a été fait dans ce
   dépôt précis et pourquoi : choix concrets, alternatives écartées, bugs
   réels rencontrés et corrigés, sortie réelle de vérification.

Les deux se renvoient l'une à l'autre par liens relatifs mais ne
dupliquent jamais leur contenu : le concept général vit dans `Notes/`, la
décision concrète vit dans le README technique du dossier concerné.

## Rigueur attendue sur les vérifications

- Ne jamais affirmer qu'une chose fonctionne sans sortie réelle
  d'exécution fournie par l'utilisateur — ce projet tourne dans son
  environnement WSL2 réel, jamais dans un sandbox contrôlé directement
  par Claude.
- Documenter aussi les bugs réels rencontrés en cours de route (pas
  seulement les succès), avec la cause réelle et le correctif réel —
  jamais fabriquer ou supposer un résultat.
- Avancer un point à la fois, vérifié avant de passer au suivant, plutôt
  que d'empiler plusieurs changements non vérifiés.

## Secrets : jamais de valeur réelle dans le dépôt ni dans la conversation

- Ne jamais écrire une valeur de secret réelle (jeton, mot de passe, clé)
  dans un fichier commité, même déjà révoquée/consommée — rédiger
  (placeholder) systématiquement avant de documenter une sortie de
  vérification.
- Si une vraie valeur secrète apparaît dans la conversation (saisie
  directe ou via sélection d'éditeur transmise automatiquement), le
  signaler explicitement plutôt que de la réutiliser silencieusement.

## Priorités et choix durables du projet

- Deux axes d'apprentissage mis en avant à égalité dans ce projet :
  **DevSecOps** (CI/CD, outillage, infrastructure, gestion des secrets)
  **et AppSec** (sécurité applicative : authentification, gestion de
  session, résistance à l'énumération, validation des entrées, modèle de
  permissions, dette OWASP-like côté code). Ne pas traiter l'AppSec comme
  secondaire par rapport à l'infrastructure — toute nouvelle
  fonctionnalité applicative (`app/backend/`) doit recevoir la même
  rigueur de conception/documentation sécurité que le travail
  d'infrastructure (Nginx, PostgreSQL, Vault, CI/CD).
- Phase 3 (CI/CD DevSecOps) et Phase 4 (gestion des secrets) sont les
  phases prioritaires pour l'apprentissage de l'utilisateur côté
  DevSecOps — viser une implémentation "pro", outils gratuits/open source
  uniquement déployés, mais documenter dans `Notes/` l'équivalent
  payant/commercial de chaque outil pour que l'utilisateur puisse se
  situer par rapport à l'industrie.
- Le site doit rester réaliste : ne pas retirer un comportement standard
  (HTTP, etc.) uniquement pour "durcir" la sécurité si ça casse un usage
  normal d'un vrai site.
- Stack applicative (Phase 5, IAM) : Node.js + Express, PostgreSQL,
  authentification construite à la main (pas de service d'identité tiers
  type Keycloak pour l'instant).
