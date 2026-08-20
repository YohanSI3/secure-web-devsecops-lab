# Notes

Journal d'apprentissage du projet. Contrairement à `docs/` (qui documentera
l'architecture et les décisions finales du projet), ce dossier trace le
**processus** : ce qui a été fait, comment, pourquoi, ce qui a été appris,
et les commandes exactes utilisées.

## Organisation

```text
Notes/
└── <outil>/
    └── <sujet>/
        ├── README.md
        └── <sous-sujet>.md
```

Exemple : `Notes/nginx/installation/README.md` documente l'installation de
Nginx (méthode, version, vérifications, ce qui a été appris).

Quand un sujet contient trop de contenu pour un seul fichier lisible, il est
découpé : le `README.md` du sous-dossier devient un index (contexte, résumé,
liens) et chaque aspect technique distinct part dans son propre fichier
nommé selon son contenu (ex. `Notes/nginx/configuration/permissions-webroot.md`,
`server-block-directives.md`) plutôt que d'accumuler dans un seul fichier.

## Convention pour chaque note

Chaque `README.md` de note suit si possible ce squelette :

- **Contexte** — pourquoi cette étape, où elle se situe dans le projet.
- **Environnement** — OS, version, plateforme.
- **Ce qui a été fait** — commandes exécutées, avec leur sortie pertinente.
- **Vérification** — comment on a confirmé que ça fonctionne.
- **Ce qui a été appris** — concepts, pièges, décisions prises et pourquoi.
  Chaque notion technique rencontrée (option de commande, terme, mécanisme)
  est expliquée en détail : définition, pourquoi elle existe, implication
  en sécurité. L'objectif est de constituer une vraie base de connaissances,
  pas juste un historique de commandes.
- **Reproductibilité** — comment recréer exactement le même setup ailleurs
  (script, version exacte, dépendances).

## Ton et style

Notes rédigées de façon impersonnelle et générale, comme un journal
technique écrit par soi-même — pas de "tu"/"vous" adressé à un lecteur.
