# Scan de secrets : comment ça détecte, et à quel moment

## Deux façons de repérer un secret

- **Motifs connus (regex)** — chaque type de secret a une forme
  reconnaissable : une clé AWS commence par `AKIA` suivi de 16
  caractères précis, un token GitHub par `ghp_`, une clé privée PEM par
  `-----BEGIN PRIVATE KEY-----`. Détection fiable (peu de faux positifs)
  mais limitée à ce qui est déjà répertorié — un nouveau format de token
  d'un service récent n'est détecté qu'une fois la règle ajoutée à
  l'outil.
- **Analyse d'entropie** — une chaîne de caractères générée aléatoirement
  (un mot de passe, une clé) a une distribution statistique différente
  d'un texte ou d'un identifiant lisible humain (`motdepasse123` a une
  entropie bien plus basse que `xK9$mPq2vL...`). Détecte des secrets sans
  motif connu, mais génère davantage de faux positifs (un hash, un UUID,
  un identifiant de commit peuvent aussi avoir une entropie élevée sans
  être un secret).

`gitleaks` ([`.github/workflows/secrets-scan.yml`](../../.github/workflows/secrets-scan.yml))
combine les deux : une bibliothèque de règles regex pour les formats
connus, complétée par une détection par entropie pour le reste.

## Trois moments où scanner, pas un seul

```text
1. AVANT le commit (hook local pre-commit)     -- le plus tôt, jamais implémenté ici
2. AU push (push protection GitHub)            -- bloque avant d'entrer dans l'historique distant
3. APRÈS coup, en CI ou en scan périodique      -- détecte ce qui est déjà passé
```

Un secret qui atteint le niveau 3 a déjà un problème structurel : même
supprimé dans un commit suivant, il reste lisible dans l'historique git
tant que l'historique n'est pas réécrit (`git filter-repo`/BFG) **et** que
toute copie déjà clonée n'est pas elle-même purgée — en pratique, un
secret commité doit être considéré compromis et **révoqué**, pas
seulement supprimé du dépôt.

Ce dépôt combine deux niveaux :

- **Niveau 2** — *push protection* de GitHub (réglage natif, gratuit sur
  dépôt public, voir [`.github/README.md`](../../.github/README.md#réglages-de-sécurité-natifs-github-settings--code-security)) :
  bloque le `git push` lui-même si un motif reconnu est détecté, avant
  qu'il n'atteigne le dépôt distant — le seul des trois niveaux qui
  empêche le problème plutôt que de le détecter après coup.
- **Niveau 3** — `gitleaks` en CI, sur tout l'historique
  (`fetch-depth: 0`), à chaque push/PR — filet de sécurité si un secret
  passe malgré tout (dépôt cloné avant l'activation de la push
  protection, par exemple), et audit répété de l'historique complet à
  chaque run plutôt qu'un scan ponctuel unique.

**Niveau 1 non implémenté** : un hook `pre-commit` local aurait
l'avantage de bloquer avant même la tentative de push, mais dépend d'une
installation par machine/développeur (facile à contourner ou à oublier
sur un nouveau clone) — la CI (niveau 3) et la push protection (niveau 2)
suffisent comme filet fiable pour ce dépôt à un seul contributeur ; un
projet avec plusieurs contributeurs gagnerait davantage à l'imposer.

## Que faire si un scan trouve réellement un secret

Dans l'ordre : **révoquer** le secret (le rendre inutile, ex. régénérer la
clé/le token côté service émetteur) **avant** de nettoyer l'historique
git — nettoyer l'historique en premier laisserait le secret valide et
exploitable pendant toute la fenêtre où quelqu'un aurait pu le récupérer
avant coup ; il n'y a par ailleurs aucune garantie qu'une copie n'ait pas
déjà été clonée ailleurs. Réécrire l'historique git est une opération
destructive sur des refs partagées, à traiter avec la même prudence que
tout `git push --force` — jamais faite ici sans confirmation explicite.
