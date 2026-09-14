# Contribuer à ce dépôt

Projet personnel, mais le workflow ci-dessous est appliqué comme s'il y
avait une équipe — c'est le point de la Phase 3 du [`ToDo.md`](ToDo.md) :
pratiquer un vrai processus DevSecOps, pas seulement le lire.

## Workflow

1. Créer une branche depuis `main` (`git checkout -b <type>/<sujet>`, ex.
   `feat/rate-limiting`, `fix/log-rotation-owner`).
2. Committer par petits incréments cohérents. Pas de format de message
   imposé strictement, mais un message qui dit *pourquoi*, pas seulement
   *quoi* (cohérent avec le ton des `Notes/`).
3. Ouvrir une pull request vers `main`. La CI (voir
   [`.github/README.md`](.github/README.md)) tourne automatiquement :
   lint de la config Nginx, SAST, scan de secrets.
4. La branche `main` est protégée (voir
   [`.github/README.md`](.github/README.md#branches-protégées)) : merge
   bloqué tant que la CI n'est pas verte. Pas d'approbation de pull
   request exigée (dépôt solo — voir la note dans `.github/README.md` sur
   ce compromis assumé), mais rien ne pousse directement sur `main`.
5. Merge en **squash** uniquement (historique de `main` linéaire, un
   commit par sujet logique — voir la configuration de branche protégée).

## Avant d'ouvrir une PR

```bash
# Lint config Nginx (si gixy est installé localement, sinon laisser la CI le faire)
gixy nginx/conf.d/*.conf nginx/snippets/*.conf nginx/sites-available/*.conf

# Scan de secrets sur le diff local
gitleaks protect --staged
```

Ces deux commandes sont volontairement les mêmes que celles exécutées par
la CI ([`.github/workflows/`](.github/workflows/)) — les lancer en local
avant de pousser évite un aller-retour CI juste pour un problème
détectable immédiatement.

## Documentation

Pour toute nouvelle implémentation, suivre le modèle à deux niveaux déjà
en place dans ce dépôt (voir [`Notes/README.md`](Notes/README.md)) :
concepts dans `Notes/<outil>/`, choix concrets dans une note technique
co-localisée avec l'artefact réel.
