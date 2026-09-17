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
| [`sast.yml`](workflows/sast.yml) | push/PR sur `main` | [Semgrep OSS](https://semgrep.dev) (`p/security-audit` + `r/bash` + `p/nodejsscan` + `p/expressjs`) |
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

### SAST : quatre rulesets ciblés, pas `--config auto`

Semgrep propose `--config auto`, qui choisit des règles selon le contenu
détecté du dépôt — mais suppose un compte Semgrep (connexion à leur
plateforme pour récupérer la configuration). Les quatre rulesets retenus
sont utilisables sans aucune authentification : `p/security-audit`
(patterns génériques : injection, crypto faible, gestion d'erreurs
dangereuse), `r/bash` (scripts shell, [`scripts/`](../scripts/)),
`p/nodejsscan` et `p/expressjs` (règles dédiées au backend Node.js/Express
de la Phase 5, IAM — [`app/backend/`](../app/backend/)). `--error` fait
échouer le job dès qu'un résultat est trouvé : une CI de sécurité qui ne
bloque jamais rien n'est qu'un tableau de bord, pas une
porte.

**Bug réel au premier run** : `--config p/bash` a échoué avec
`Failed to download configuration ... HTTP 404` — ce pack n'existe pas
dans le [Semgrep Registry](https://semgrep.dev/explore). Deux préfixes
existent et ne sont pas interchangeables : `p/<nom>` référence un
*pack* curé (une sélection éditorialisée, ex. `p/security-audit`),
`r/<langage>` référence *toutes* les règles publiées pour un langage
donné, sans curation éditoriale. Il n'existe pas de pack curé pour bash,
seulement la collection complète par langage — d'où `r/bash` plutôt que
`p/bash`. Vérifié directement via `curl -sL -o /dev/null -w '%{http_code}'
https://semgrep.dev/c/<config>` avant de corriger, plutôt que de deviner
un autre nom au hasard.

**Premier scan réel (`r/bash` + `p/security-audit`, 232 règles, 89
fichiers) : 1 finding, faux positif.** `generic.nginx.security.insecure-ssl-version`
s'est déclenché sur
[`nginx/conf.d/security.conf`](conf.d/security.conf) — mais sur un
**commentaire** qui *décrit* l'ancienne valeur stock
`ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;` pour expliquer pourquoi
elle est remplacée ailleurs (voir
[`Notes/nginx/tls/protocoles-tls-heritage-et-fusion.md`](../Notes/nginx/tls/protocoles-tls-heritage-et-fusion.md)),
pas sur une directive active — le vrai `ssl_protocols` du dépôt
([`nginx/snippets/tls-hardening.conf`](snippets/tls-hardening.conf))
restreint bien à TLSv1.2/1.3 seuls. Semgrep n'a pas de notion de
"commentaire explicatif citant une valeur dangereuse pour la documenter" :
il matche du texte, pas une intention.

**Premier correctif tenté, insuffisant** : une annotation
`# nosemgrep: <rule-id>` sur la ligne précédant le match (syntaxe
officiellement documentée : *"at the first line or preceding line of the
pattern match"*) n'a **pas** supprimé le finding au run suivant — le
`rule-id` `generic.nginx.security.*` tourne sous le moteur **generic**
de Semgrep (pattern-matching sur texte brut, sans analyse syntaxique du
langage cible), qui ne reconnaît apparemment pas `#` comme introduisant
un commentaire porteur d'une directive `nosemgrep` de la même façon qu'un
langage réellement parsé. Constaté empiriquement (le finding réapparaît
identique après le premier correctif), pas déduit de la documentation
seule.

**Correctif retenu** : reformuler le commentaire pour ne plus reproduire
littéralement la syntaxe `ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;`
qui déclenche la règle, en décrivant le même fait en prose (« l'ensemble
hérité de protocoles TLS du paquet Ubuntu, incluant encore les deux
versions dépréciées ») plutôt qu'en citant le texte exact d'une directive
dangereuse. Le détail syntaxique complet reste disponible dans
[`Notes/nginx/tls/protocoles-tls-heritage-et-fusion.md`](../Notes/nginx/tls/protocoles-tls-heritage-et-fusion.md)
(fichier `.md`, hors du périmètre de cette règle — elle ne s'applique
qu'aux fichiers de configuration, pas à la documentation). Plus robuste
qu'une suppression dont le mécanisme s'est révélé peu fiable ici : la
CI ne dépend plus de la reconnaissance d'une annotation, seulement de
l'absence du motif recherché.

**Premier scan sur du vrai JS (`p/nodejsscan` + `p/expressjs`, 218
règles, 114 fichiers) : 12 findings, triés un par un plutôt qu'une
suppression en bloc.**

- **6 `good_helmet_checks`** (`helmet_header_dns_prefetch`, `_hsts`,
  `_ienoopen`, `_nosniff`, `_x_powered_by`, `_xss_filter`) —
  contre-intuitif : ce sont des règles qui **confirment** qu'un en-tête
  est bien présent (le nom du rule-id le dit : "good"), pas des
  détections de problème. njsscan les classe en sévérité bloquante par
  cohérence avec le reste du pack, sans distinguer "positif" de
  "négatif" au niveau du `--error` de Semgrep.
- **5 réglages de cookie de session non explicites** (`domain`, `path`
  ×2 pack, `expires`) — décision au cas par cas plutôt qu'une suppression
  globale : `path` **corrigé** (`path: '/'` ajouté explicitement, sans
  changement de comportement réel puisque `/` était déjà la valeur par
  défaut) ; `domain` **volontairement laissé absent** (la portée la plus
  étroite possible pour un cookie de session — envoyé uniquement à
  l'hôte exact — est le comportement voulu ici, le fixer explicitement
  *élargirait* la portée plutôt que de la resserrer) ; `expires`
  **volontairement remplacé par `maxAge`** (la documentation
  d'`express-session` recommande elle-même `maxAge`, une durée relative
  recalculée à chaque envoi, plutôt que `expires`, une date absolue plus
  simple à mal régler en oubliant de la renouveler).

**`nosemgrep` : deux échecs de suite pour deux raisons différentes,
avant un placement correct.** Les 9 findings ci-dessus (`domain` et
`expires`, volontaires, plus les 6 `good_helmet_checks`) ont d'abord été
« supprimés » via `# nosemgrep: <rule-id>` — sans effet au run suivant,
un deuxième échec après celui déjà rencontré sur
`generic.nginx.security.*` (voir plus haut), mais pour une **raison
différente** cette fois : la syntaxe officielle exige que l'annotation
soit *"at the first line or preceding line of the pattern match"* —
**immédiatement** précédente, pas seulement quelque part au-dessus. Le
premier essai plaçait `nosemgrep` en première ligne d'un bloc de
commentaire explicatif de plusieurs lignes, avec le texte de
justification *entre* l'annotation et le code réel — une lecture trop
littérale de "avant le code" plutôt que "la ligne juste avant". Corrigé
en inversant l'ordre (justification d'abord, `nosemgrep` en dernière
ligne de commentaire, collée au code) dans
[`app/backend/src/index.js`](../app/backend/src/index.js). Lié au point
noté plus haut sur `generic.*` (le moteur derrière la règle importe pour
la fiabilité de `nosemgrep`), mais distinct : cette fois le moteur était
le bon (vrai parseur JS), l'erreur était uniquement de placement —
*deux catégories d'échec différentes, à ne pas confondre* : l'une tient
au moteur de la règle, l'autre à une lecture trop relâchée de "ligne
précédente".
- **1 `curl-pipe-bash`** dans
  [`scripts/install-nodejs.sh`](../scripts/install-nodejs.sh) — légitime,
  pas de faux positif ici. Corrigé en séparant le téléchargement de
  l'exécution (`curl -o fichier` puis `bash fichier`, plutôt qu'un pipe
  direct) : ne change pas le modèle de confiance de fond (NodeSource
  reste la source, toujours en HTTPS), mais supprime l'exécution en flux
  continu que la règle ciblait précisément, et redevient inspectable
  entre les deux étapes.

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

**Bug réel rencontré au premier run** : le job a échoué immédiatement sur
l'événement `pull_request` avec `GITHUB_TOKEN is now required to scan
pull requests` — `gitleaks-action` (depuis sa v2) appelle l'API GitHub
pour récupérer le diff exact de la PR, et a donc besoin du token
automatique du workflow, jamais fourni par défaut. Corrigé en passant
`env: GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}` explicitement à l'étape
— `secrets.GITHUB_TOKEN` est généré automatiquement par GitHub pour
chaque run (pas un secret à créer soi-même), simplement pas injecté dans
l'environnement d'une action tierce sans le déclarer.

**Vraie détection, pas un faux positif — outil qui fait exactement son
travail** : `gitleaks` a bloqué une PR (Phase 5, correctif `proxy_pass`)
en repérant un vrai jeton de réinitialisation de mot de passe
(`generic-api-key`, entropie ~3.8) collé tel quel dans
[`app/backend/README.md`](../app/backend/README.md) comme "sortie réelle"
d'un test de vérification. Jeton à usage unique, déjà consommé par le
`reset-password` qui suivait dans la même séquence de test, et lié à un
compte `test@example.com` qui n'existe que dans l'environnement de
développement local — donc sans risque exploitable réel. Corrigé en
redactant la valeur (remplacée par un texte explicite plutôt que par le
jeton), pas en supprimant ou en excluant la règle : committer une valeur
qui a la forme d'un secret dans une documentation reste une mauvaise
pratique à corriger, même quand le secret précis n'a plus de valeur
d'exploitation — exactement le genre de réflexe que ce scanner est censé
imposer.

### Découverte urgente en cours de route : dépréciation Node 20

Une pull request automatique de Dependabot proposant de passer
`gitleaks/gitleaks-action` en v3 a alerté sur un sujet plus large que ce
seul paquet : **GitHub retire Node 20 des runners hébergés le 16
septembre 2026**. Toute action encore basée sur Node 20 —
`actions/checkout@v4`, `actions/upload-artifact@v4`, et
`gitleaks-action@v2`, utilisées dans les quatre workflows de ce dépôt —
cesse alors de fonctionner, indépendamment de tout bug de configuration.
Mis à jour partout par anticipation plutôt que d'attendre l'échéance :

- `actions/checkout@v4` → `@v7` (les 4 workflows)
- `actions/upload-artifact@v4` → `@v7` ([`build-artifact.yml`](workflows/build-artifact.yml))
- `gitleaks/gitleaks-action@v2` → `@v3` ([`secrets-scan.yml`](workflows/secrets-scan.yml)) —
  aucun changement d'entrées/comportement selon le guide de migration du
  projet, seulement le runtime Node ; `GITHUB_TOKEN` reste requis en v3
  comme en v2, ce correctif-ci restait donc nécessaire indépendamment de
  la version.

Repéré en vérifiant directement les releases (`GET /repos/<owner>/<repo>/releases/latest`
sur `actions/checkout`, `actions/upload-artifact`) et le
[guide de migration de gitleaks-action](https://github.com/gitleaks/gitleaks-action#migrating-from-v2-to-v3)
plutôt qu'en supposant un numéro de version au hasard.

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

## État vérifié

Les 3 checks bloquants tournent tous au vert sur la première PR réelle
(`feat/phase3-devsecops-ci`) après correctifs :

```text
gitleaks  succeeded in 7s
lint      succeeded in 16s
semgrep   succeeded in 30s
```

`build-artifact.yml` ne se déclenche que sur push vers `main` (pas sur
PR, volontairement — voir la table plus haut) : confirmé fonctionnel
juste après le merge de cette PR (`build succeeded in 6s`), artefact
`static-site-<sha>.tar.gz` + checksum produits sans intervention
manuelle.

**Les 4 workflows du pipeline sont donc vérifiés de bout en bout, en
conditions réelles, pas seulement relus.**

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

Gratuits sur un dépôt public, sans fichier à committer. L'intitulé exact
de l'UI a changé depuis l'écriture de cette section (regroupé sous
« Advanced Security ») — activés :

- **Private vulnerability reporting** — nécessaire pour que le lien
  `.../security/advisories/new` cité dans [`SECURITY.md`](../SECURITY.md)
  fonctionne réellement.
- **Dependency graph** — prérequis technique de Dependabot.
- **Dependabot alerts**, **Dependabot security updates**,
  **Grouped security updates** (regroupe les PR de sécurité par
  gestionnaire de paquets plutôt qu'une par dépendance), **Dependabot
  version updates** (pilote l'exécution effective de
  [`dependabot.yml`](dependabot.yml)).
- **Push protection** (sous *Secret Protection*) — bloque un push
  contenant un secret d'un pattern reconnu, avant même qu'il n'atteigne
  l'historique — la seule protection de ce document qui agit *avant* que
  le problème n'existe dans le dépôt plutôt que de le détecter après
  coup. Le scan de base (alertes aux partenaires pour un secret détecté)
  est déjà actif par défaut sur un dépôt public, sans toggle séparé.

**Délibérément pas activé : CodeQL analysis** (sous *Code scanning*).
CodeQL — le SAST natif de GitHub, gratuit sur dépôt public — n'analyse
que des langages applicatifs (JavaScript, Python, Java, Go, C/C++, C#,
Ruby, Swift). Ce dépôt ne contient aucun de ces langages (bash, config
Nginx, Markdown) : l'activer aujourd'hui n'analyserait rien d'utile.
Semgrep OSS ([`sast.yml`](workflows/sast.yml)) reste le SAST pertinent
tant que ça n'a pas changé — CodeQL redevient pertinent le jour où une
stack applicative dans un langage supporté est ajoutée (voir
[`Notes/devsecops/paysage-outillage.md`](../Notes/devsecops/paysage-outillage.md)).
`Copilot Autofix` et `AI findings` dépendent tous deux de CodeQL, donc
sans effet tant qu'il reste désactivé.
