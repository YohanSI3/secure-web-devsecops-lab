# Notes

Journal d'apprentissage du projet : concepts, fonctionnement des
technologies utilisées, pourquoi on fait les choses en général — de quoi
comprendre un sujet avant de l'implémenter. Rédigé comme un cours qu'on se
donne à soi-même, pas comme la documentation d'un produit.

## Notes vs documentation technique

`Notes/` ne documente **pas** les choix d'implémentation propres à ce
projet — ceux-là vivent en dehors de ce dossier, **co-localisés avec
l'artefact technique réel** qu'ils concernent (`nginx/README.md`,
`scripts/README.md`, `firewall/README.md`, etc.) : quelles règles/valeurs
ont été retenues ici, pourquoi, comment vérifier que c'est bien ce qui
tourne. Objectif : qu'un ingénieur qui veut comprendre comment la prod de
ce lab est réellement faite puisse lire directement le dossier technique
concerné, sans repasser par tout le raisonnement pédagogique — et
inversement, qu'on puisse relire `Notes/` pour comprendre *pourquoi* un
choix documenté techniquement a été fait ainsi plutôt qu'autrement.

En résumé :
- `Notes/<outil>/` → cours (comment ça marche, pourquoi en général),
- `<dossier-technique>/README.md` → décision (ce qu'on a choisi ici, pour
  ce projet, et comment le vérifier).

Chaque note technique renvoie vers la note `Notes/` correspondante pour le
contexte d'apprentissage, et chaque note `Notes/` renvoie vers la note
technique une fois l'implémentation faite.

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
