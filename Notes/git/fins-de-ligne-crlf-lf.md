# Fins de ligne : CRLF (Windows) vs LF (Unix), et `core.autocrlf`

## Le problème rencontré

En exécutant `bash scripts/install-nginx.sh` depuis WSL sur un dépôt cloné
côté Windows (`/mnt/c/Users/.../secure-web-devsecops-lab`), échec
immédiat :

```text
: invalid option name.sh: line 4: set: pipefail
```

Message trompeur en apparence (fragments qui semblent inversés/collés),
mais explicable : la ligne 4 du script est `set -euo pipefail`. Le fichier
avait des fins de ligne **CRLF** (`\r\n`) plutôt que **LF** (`\n`) seul. Le
caractère `\r` n'est pas un séparateur pour le shell — il fait partie du
dernier mot de la ligne. Bash a donc reçu `pipefail\r` comme nom d'option
pour `set -o`, qui ne correspond à aucune option connue (`pipefail` ≠
`pipefail\r`), d'où `invalid option name`. Le `\r` présent *dans le message
d'erreur lui-même* (puisqu'il cite l'argument fautif) ramène ensuite le
curseur du terminal en début de ligne avant la fin de l'affichage, d'où
l'effet de texte qui se chevauche/s'inverse à l'écran — pas une corruption
du message, un artefact d'affichage.

## Pourquoi seulement sur cette machine, alors que le dépôt marchait ailleurs

`git config core.autocrlf` valait `true` sur cette machine Windows (valeur
par défaut de l'installateur Git pour Windows). Avec `autocrlf=true`, Git
convertit **LF → CRLF** à chaque `checkout` (dont un `clone`), et
inversement **CRLF → LF** à chaque `add`/`commit` — pensé à l'origine pour
que les fins de ligne "aient l'air normales" dans les éditeurs Windows,
sans changer ce qui est stocké dans les objets Git (toujours LF). Ce
comportement s'applique par défaut à **tout** fichier texte, y compris des
scripts destinés à être exécutés par un interpréteur qui, lui, ne tolère
aucun `\r` parasite.

Le dépôt fonctionnait auparavant simplement parce que l'exécution réelle se
faisait depuis un environnement où le clone avait été fait directement en
Linux (pas de conversion CRLF) — le bug était présent dans le dépôt depuis
le début côté Windows, seulement jamais déclenché.

## Le correctif : `.gitattributes`

```gitattributes
* text=auto eol=lf
*.sh  text eol=lf
*.conf text eol=lf
```

- `text=auto` — laisse Git détecter automatiquement les fichiers texte
  (vs binaires, qu'il ne faut jamais toucher aux octets).
- `eol=lf` — force la fin de ligne **LF** au checkout, quel que soit
  `core.autocrlf` de la machine cliente. Contrairement à `core.autocrlf`
  (réglage local, par utilisateur/machine, non versionné), `.gitattributes`
  est **versionné dans le dépôt** : la règle s'applique pour n'importe qui
  clone ce dépôt, sur n'importe quelle machine, sans dépendre de la config
  Git personnelle de chacun.
- Déclarations explicites `*.sh`/`*.conf` en plus de la règle générale : les
  deux catégories de fichiers où une fin de ligne parasite a un impact
  fonctionnel réel (script interprété, directive de config nginx), pas
  seulement cosmétique — les rendre explicites documente l'intention plutôt
  que de compter implicitement sur `* text=auto eol=lf` seul.

**Point important** : `.gitattributes` ne corrige que les *futurs*
checkouts. Les fichiers déjà présents dans l'arbre de travail au moment où
la règle est ajoutée gardent leurs fins de ligne existantes tant qu'ils ne
sont pas réécrits — d'où la nécessité d'une normalisation ponctuelle des
fichiers déjà versionnés (ici faite via `sed -i 's/\r$//'` sur chaque
fichier suivi par Git, plus sûr qu'un outil dédié type `dos2unix` absent
par défaut, et sans risque sur le contenu UTF-8 accentué du dépôt : `\r`
est l'octet `0x0D`, qui n'apparaît jamais comme partie d'une séquence
multi-octet UTF-8).

## Pourquoi ne pas juste mettre `core.autocrlf=false` ou `input`

Aurait réglé le problème *localement*, sur cette seule machine, pour cet
seul utilisateur — mais silencieusement, sans trace dans le dépôt, et sans
protection pour quiconque clone ce dépôt ailleurs avec `autocrlf=true`
(valeur par défaut très répandue sous Windows). `.gitattributes` déplace le
correctif du poste de travail vers le dépôt lui-même : la bonne échelle
pour un projet dont un objectif explicite est la reproductibilité
multi-machine (cf.
[`Notes/nginx/installation/README.md`](../nginx/installation/README.md)).
