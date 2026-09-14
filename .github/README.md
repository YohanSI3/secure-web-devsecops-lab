# CI/CD — documentation technique

Choix d'implémentation concrets de la Phase 3 (`ToDo.md`) : dépôt Git
propre, CI, scans de sécurité automatisés, artefacts de build contrôlés.
Pour le fonctionnement général (SAST/SCA/secrets scanning, modèles de
protection de branche, paysage des outils y compris payants), voir
[`Notes/devsecops/`](../Notes/devsecops/README.md).

**Choix transversal pour toute cette phase** : uniquement des outils
gratuits/open source réellement déployés ici. Chaque outil retenu est
accompagné, dans `Notes/devsecops/`, de sa référence commerciale
équivalente (ce qui se fait aujourd'hui dans l'industrie), pour
alimenter une veille personnelle sans dépendre d'une licence payante pour
ce lab.

## Pipeline CI (`workflows/`)

| Workflow | Déclencheur | Ce qu'il fait |
|---|---|---|
| [`nginx-lint.yml`](workflows/nginx-lint.yml) | push/PR sur `main` | `nginx -t` + [gixy](https://github.com/yandex/gixy) sur la config assemblée |
| [`sast.yml`](workflows/sast.yml) | push/PR sur `main` | [Semgrep OSS](https://semgrep.dev) (`p/security-audit` + `p/bash`) |
| [`secrets-scan.yml`](workflows/secrets-scan.yml) | push/PR sur `main` | [gitleaks](https://github.com/gitleaks/gitleaks) sur tout l'historique |
| [`build-artifact.yml`](workflows/build-artifact.yml) | push sur `main` | package + checksum du site statique |

### Nginx lint : pourquoi assembler l'arborescence plutôt que juste `nginx -t` sur les fichiers du dépôt

Les fichiers de `nginx/` sont des **fragments** (`conf.d/`, `snippets/`,
`sites-available/`) pensés pour être reliés à un `/etc/nginx/` complet
(voir
[`Notes/nginx/configuration/repo-vs-etc-nginx.md`](../Notes/nginx/configuration/repo-vs-etc-nginx.md)) —
ils ne forment pas une config autonome (pas de `nginx.conf` racine, des
chemins `include` relatifs à `/etc/nginx/`). Le job installe donc Nginx
sur le runner et reconstitue la même arborescence que
[`scripts/deploy-nginx-config.sh`](../scripts/deploy-nginx-config.sh),
par copie plutôt que par symlink (le runner est éphémère, rien à faire
survivre après le job).

`nginx -t` vérifie aussi que les fichiers `ssl_certificate`/
`ssl_certificate_key` référencés **existent et sont lisibles**, pas
seulement la syntaxe — d'où la génération de certificats jetables
(`openssl req -x509 ...`, jamais commités, recréés à chaque run) plutôt
que de dépendre de la vraie CA locale du lab (`.tls/`, non versionnée et
absente du runner CI par construction, voir
[`Notes/nginx/tls/local-ca-et-chaine-de-confiance.md`](../Notes/nginx/tls/local-ca-et-chaine-de-confiance.md)).

`gixy` tourne ensuite sur `/etc/nginx/nginx.conf` une fois l'arborescence
en place : il suit les `include` comme le ferait Nginx lui-même, donc a
besoin de la même reconstitution que `nginx -t`.

### SAST : `p/security-audit` + `p/bash`, pas `--config auto`

Semgrep propose `--config auto`, qui choisit des règles selon le contenu
détecté du dépôt — mais suppose un compte Semgrep (connexion à leur
plateforme pour récupérer la configuration). `p/security-audit` et
`p/bash` sont des rulesets publics du
[Semgrep Registry](https://semgrep.dev/explore), utilisables sans aucune
authentification : `p/security-audit` couvre des patterns génériques
(injection, crypto faible, gestion d'erreurs dangereuse), `p/bash` cible
spécifiquement les scripts shell — la majorité du code de ce dépôt
([`scripts/`](../scripts/)). `--error` fait échouer le job dès qu'un
résultat est trouvé : une CI de sécurité qui ne bloque jamais rien n'est
qu'un tableau de bord, pas une porte.

### Secrets scan : gitleaks en CI, en plus du secret scanning natif GitHub

Ce dépôt étant public, GitHub propose gratuitement son propre
**secret scanning** (détection continue, y compris *push protection* qui
peut bloquer un push contenant un secret reconnu avant même qu'il
n'atteigne le dépôt) — voir la checklist de réglages en fin de ce
document. `gitleaks` en CI n'est pas redondant : il scanne **tout
l'historique** à la demande (`fetch-depth: 0`), avec des règles
personnalisables, sur chaque push/PR — complémentaire, pas un doublon,
du scanning continu de GitHub. Voir
[`Notes/devsecops/secrets-scanning.md`](../Notes/devsecops/secrets-scanning.md)
pour le détail de cette complémentarité.

### Artefacts de build contrôlés

`build-artifact.yml` empaquette [`app/static-site/`](../app/static-site/)
en `.tar.gz` nommé par le SHA court du commit, accompagné de son
`sha256sum` — la définition minimale d'un artefact "contrôlé" : traçable
jusqu'à la source exacte (commit), vérifiable (checksum), produit
uniquement par un pipeline automatisé (jamais construit ni uploadé
manuellement). `actions/upload-artifact` avec `retention-days: 30` évite
une accumulation indéfinie côté GitHub.

## Dependabot

[`dependabot.yml`](dependabot.yml) — surveille uniquement les versions des
actions GitHub référencées dans `workflows/` (seule vraie dépendance
externe du dépôt aujourd'hui ; à étendre le jour où une stack applicative
avec gestionnaire de paquets est ajoutée).

**Tags (`@v4`) plutôt que SHA de commit** : épingler par SHA complet
(pratique recommandée par les guides de durcissement GitHub Actions les
plus stricts) empêcherait un mainteneur d'action de changer le
comportement sans que ça se voie dans le diff — mais rendrait aussi les
fichiers de workflow beaucoup moins lisibles à la main. Choix retenu ici :
tag + Dependabot, qui ouvre une pull request (donc une revue humaine et un
passage CI) à chaque nouvelle version plutôt qu'une dérive silencieuse —
un compromis lisibilité/rigueur documenté, pas un oubli. Voir
[`Notes/devsecops/`](../Notes/devsecops/README.md) pour la pratique plus
stricte (SHA-pinning) à connaître si ce compromis doit être resserré plus
tard.

## Branches protégées

Pas de fichier à committer — réglage du dépôt GitHub, à faire dans
*Settings > Branches > Add branch protection rule* pour `main` :

- **Require a pull request before merging** — coché. Personne (pas même
  l'unique mainteneur de ce dépôt solo) ne pousse directement sur `main`.
- **Require approvals** — mis à **0**. Compromis assumé et documenté :
  un dépôt solo n'a personne d'autre pour approuver ; exiger une
  approbation bloquerait toute PR indéfiniment. La vraie porte de qualité
  ici, ce sont les checks CI ci-dessous, pas une revue humaine absente
  par construction.
- **Require status checks to pass before merging** — coché, avec les 3
  checks CI (`nginx-lint`, `sast (semgrep)`, `gitleaks`) sélectionnés
  comme obligatoires. `build-artifact` n'est volontairement **pas**
  requis ici : c'est un artefact de sortie, pas une porte de qualité —
  son échec ne doit pas bloquer un merge par ailleurs valide.
- **Require branches to be up to date before merging** — coché (évite de
  merger une branche testée contre un `main` déjà obsolète).
- **Require linear history** — coché (impose le squash-merge, historique
  de `main` lisible en une ligne par sujet — voir
  [`CONTRIBUTING.md`](../CONTRIBUTING.md)).
- **Do not allow bypassing the above settings** — coché, y compris pour
  les administrateurs (sinon la protection ne protège que les autres,
  jamais soi-même en cas d'urgence perçue).
- **Restrict force pushes** et **Restrict deletions** — cochés.

## Réglages de sécurité natifs GitHub (Settings > Code security)

Gratuits sur un dépôt public, sans configuration par fichier :

- **Secret scanning** — Enable.
- **Push protection** — Enable (bloque un push contenant un secret d'un
  pattern reconnu, avant même qu'il n'atteigne l'historique — la seule
  protection de ce document qui agit *avant* que le problème n'existe
  dans le dépôt plutôt que de le détecter après coup).
- **Dependabot alerts** — Enable.
- **Dependabot security updates** — Enable (ouvre automatiquement une PR
  de correctif quand une vulnérabilité connue est trouvée dans une
  dépendance surveillée).
