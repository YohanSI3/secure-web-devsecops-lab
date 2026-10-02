# HashiCorp Vault — documentation technique

Phase 4 du `ToDo.md` : gestion des secrets applicatifs réels (mot de
passe PostgreSQL, `SESSION_SECRET`) au runtime, au-delà de leur simple
non-commit (déjà couvert par gitleaks/push protection, Phase 3). Pour le
fonctionnement général de Vault (scellé/descellé, jeton racine, secrets
statiques vs dynamiques), voir [`Notes/vault/`](../Notes/vault/README.md).

## État actuel

Installé, configuré, initialisé et descellé — jeu de clés de descellement
et jeton racine déjà renouvelés une fois (voir « Bug réel » plus bas).
Aucun secrets engine encore activé : prochaine étape, voir « Reste à
faire » plus bas.

## Installation : dépôt apt officiel HashiCorp, pas les dépôts Ubuntu

[`scripts/install-vault.sh`](../scripts/install-vault.sh) — Vault n'est
pas empaqueté dans les dépôts Ubuntu, contrairement à PostgreSQL ou
fail2ban. Même exception déjà documentée pour Node.js
([`Notes/nodejs/installation/README.md`](../Notes/nodejs/installation/README.md)) :
le dépôt HashiCorp est le canal de distribution officiellement recommandé
par l'éditeur lui-même pour les systèmes basés sur apt, pas un PPA tiers
non maîtrisé. Clé GPG téléchargée puis importée séparément (pas un
`curl | gpg` direct) — même raisonnement que la séparation
téléchargement/exécution déjà appliquée à `install-nodejs.sh` pour éviter
le schéma `curl-pipe-bash` repéré par Semgrep, ici appliqué par précaution
même si gpg n'est pas un interpréteur de commandes. Version résolue
dynamiquement puis épinglée (`apt-mark hold`), même logique que
PostgreSQL.

## Configuration (`config.hcl`)

[`config.hcl`](config.hcl), déployé par
[`scripts/deploy-vault-config.sh`](../scripts/deploy-vault-config.sh) vers
`/etc/vault.d/vault.hcl` (copié et `chown vault:vault`, pas symlinké —
même raisonnement que
[`postgresql/README.md`](../postgresql/README.md) pour `pg_hba.conf` :
le service tourne sous un utilisateur dédié, pas celui qui possède le
dépôt).

### Stockage : `file`, pas Consul/Raft

Backend de stockage le plus simple proposé par Vault — adapté à une
instance unique sans besoin de haute disponibilité (contrairement à
Consul ou au stockage intégré `raft`, pensés pour un cluster
multi-nœuds). Cohérent avec l'échelle de ce lab : apprendre le
fonctionnement de Vault lui-même, pas construire un cluster de
production.

### TLS désactivé (`tls_disable = true`) sur le listener

Même raisonnement déjà documenté pour la connexion Node → PostgreSQL
([`postgresql/README.md#tls--pas-activé-pour-la-connexion-node--postgresql-et-pourquoi`](../postgresql/README.md#tls--pas-activé-pour-la-connexion-node--postgresql-et-pourquoi)) :
le listener Vault n'écoute que sur `127.0.0.1`, jamais quitté par le
trafic réseau physique — aucun tiers sur le réseau ne peut intercepter de
toute façon. Vault lui-même recommande fortement TLS même en local pour
un usage réel ; décision documentée explicitement ici comme un compromis
assumé pour ce lab (boucle locale uniquement), pas un oubli.

### Interface web activée (`ui = true`)

Choix pédagogique délibéré : l'UI Vault permet d'explorer visuellement
les secrets engines, policies et leases pendant l'apprentissage, sans
exposition supplémentaire puisqu'elle écoute sur la même adresse que
l'API elle-même (`127.0.0.1:8200`, jamais exposée au-delà) — même niveau
d'accès que l'API, pas un risque ajouté.

## Bug réel : fichier de clés non ignoré par Git, secrets collés en clair

Au moment d'initialiser Vault (`vault operator init`), deux erreurs
distinctes, découvertes en pratiquant plutôt que supposées :

1. **Les clés de descellement et le jeton racine ont été collés en clair
   dans la conversation** utilisée pour piloter ce projet, malgré une
   consigne explicite de ne jamais le faire — l'historique d'une
   conversation n'est pas un coffre-fort. Traité comme une compromission
   réelle plutôt qu'ignoré : voir « Remédiation » plus bas.
2. **`.gitignore` contenait déjà une règle visant à exclure ce fichier
   (`Vault_keys.txt`), mais le fichier réel sauvegardé s'appelait
   `vault/Vault_keys` (sans extension `.txt`, dans le dossier `vault/`)**
   — la règle ne matchait donc rien, `git status` montrait le fichier
   comme non suivi (`??`), à un `git add -A` près d'atterrir dans
   l'historique d'un dépôt public. Corrigé par un motif plus robuste
   (`vault/Vault_keys*` et `Vault_keys*`, voir [`.gitignore`](../.gitignore))
   — mais la vraie correction est de ne **jamais** écrire ce fichier dans
   le dépôt du tout : la sortie de `vault operator init`/`rekey` doit
   vivre hors du dépôt dès le départ (ex. `~/vault-init-DO-NOT-COMMIT.txt`),
   `.gitignore` n'est qu'un filet de sécurité, pas la protection
   principale.

### Remédiation : rekey + régénération du jeton racine

Rien n'était encore stocké dans Vault (aucun secrets engine activé) au
moment de la découverte — mais les clés exposées dans la conversation ont
quand même été traitées comme compromises, par rigueur plutôt que par
nécessité technique immédiate :

1. `vault operator rekey` — nouveau jeu de 5 clés de descellement
   (seuil 3), autorisé par les 3 anciennes clés une dernière fois ; les
   anciennes clés cessent alors de fonctionner.
2. `vault operator generate-root` — nouveau jeton racine, autorisé par
   les nouvelles clés de descellement (pas par l'ancien jeton).
3. `vault token revoke <ancien jeton>`, authentifié avec le nouveau,
   pour achever la révocation de l'ancien jeton racine.

Voir [`Notes/vault/README.md#rekey-et-generate-root--les-deux-cérémonies-durgence`](../Notes/vault/README.md#rekey-et-generate-root--les-deux-cérémonies-durgence)
pour le détail de ces deux opérations.

**Bug opérationnel rencontré en route, sans rapport avec la compromission
elle-même** : `vault operator rekey -init` lancé avec `sudo` a d'abord
échoué (`http: server gave HTTP response to HTTPS client`) — `sudo`
repart d'un environnement propre par défaut, `VAULT_ADDR` (positionné
seulement dans le shell de l'utilisateur) n'était donc pas transmis, et le
CLI retombe sur son adresse par défaut (`https://127.0.0.1:8200`, TLS) au
lieu de celle réellement configurée (HTTP, `tls_disable = true` dans
[`config.hcl`](config.hcl)). `sudo` n'est de toute façon pas nécessaire
ici : le CLI `vault` n'est qu'un client HTTP vers l'API locale, aucun
privilège élevé requis. Deuxième échec après retrait de `sudo`, cette
fois `403 permission denied` sur `sys/rekey/init` : contrairement aux
parts de clé soumises ensuite (`sys/rekey/update`, où posséder une part
*est* l'autorisation), **démarrer** une cérémonie de rekey est une action
administrative qui exige un jeton authentifié (`VAULT_TOKEN`) — ici,
l'ancien jeton racine, encore valide jusqu'à l'achèvement du rekey.

Séquence réelle complète, dans l'ordre :

```text
$ vault operator rekey -init -key-shares=5 -key-threshold=3
Error initializing rekey: Put "https://127.0.0.1:8200/...": http: server gave HTTP response to HTTPS client
# -> sudo utilisé par erreur, VAULT_ADDR perdu ; retiré

$ vault operator rekey -init -key-shares=5 -key-threshold=3
Error initializing rekey: ... 403 permission denied
# -> VAULT_TOKEN (ancien jeton racine) manquant ; exporté

$ export VAULT_TOKEN=<ancien jeton racine>
$ vault operator rekey -init -key-shares=5 -key-threshold=3
Nonce    195b66ea-2f66-020d-4bc0-4c8fb1558525
Rekey Progress    0/3
New Shares    5
New Threshold    3

$ vault operator rekey -nonce=195b66ea-2f66-020d-4bc0-4c8fb1558525   # x3, une ancienne clé à chaque fois
Rekey Progress    1/3
Rekey Progress    2/3
Key 1: ...
Key 2: ...
Key 3: ...
Key 4: ...
Key 5: ...
# -> 5 nouvelles clés de descellement, anciennes invalidées

$ vault operator generate-root -init
Nonce    <...>
OTP      <...>

$ vault operator generate-root -nonce=<...>   # x3, une NOUVELLE clé à chaque fois
# -> "Encoded Token" après la 3e

$ vault operator generate-root -decode=<encoded> -otp=<otp>
# -> nouveau jeton racine en clair, enregistré localement hors du dépôt

$ VAULT_TOKEN=<nouveau jeton racine> vault token revoke <ancien jeton racine>
$ vault status
```

Confirme la chaîne complète : anciennes clés de descellement et ancien
jeton racine (tous deux exposés dans la conversation) révoqués/remplacés
avant toute utilisation réelle de Vault pour stocker un secret.

Révocation effective confirmée :

```text
$ vault token revoke <ancien jeton racine, révoqué -- valeur redactée>
Success! Revoked token (if it existed)
```

**Point d'attention retenu, pas uniquement sur Vault** : un outil (IDE,
éditeur) qui transmet automatiquement ce qui est sélectionné/affiché à
l'écran peut réexposer un secret après coup, même une fois la bonne
pratique suivie pour la saisie initiale (le nouveau jeton racine généré
pour remplacer l'ancien a lui-même été vu via une sélection d'éditeur sur
le fichier local où il avait été sauvegardé). La vraie protection n'est
donc pas seulement "ne pas coller un secret dans un outil" mais aussi "ne
pas garder ouvert, dans un outil qui partage son contexte, un fichier qui
en contient" — fermer/déplacer un tel fichier dès qu'il n'est plus
nécessaire à l'écran, pas seulement après usage initial.

**Dernier filet de sécurité qui a effectivement fonctionné** : malgré
tout ce qui précède, l'ancien jeton racine (déjà révoqué à ce stade, donc
mort) a quand même été écrit en clair dans une première version de cette
section — erreur de documentation, pas de saisie cette fois. `git push`
a été **rejeté par la push protection GitHub** (`GH013`, détection
`HashiCorp Vault Root Service Token`) avant d'atteindre le dépôt distant.
Corrigé en redactant la valeur et en amendant le commit local (jamais
poussé avec succès, donc rien à réécrire côté remote). Exactement le
scénario pour lequel ce filet existe (voir
[`.github/README.md#secrets-scan--gitleaks-en-ci-en-plus-du-secret-scanning-natif-github`](../.github/README.md#secrets-scan--gitleaks-en-ci-en-plus-du-secret-scanning-natif-github)) :
une erreur humaine (ou ici, de l'assistant générant la documentation) a
bien lieu, et c'est la couche automatisée qui l'arrête avant publication —
pas la vigilance individuelle seule, qui avait déjà failli deux fois dans
cet incident précis.

## Reste à faire

- Initialisation + descellement (première vérification réelle à faire
  avant de poursuivre).
- Secrets engine `database` pour PostgreSQL : identifiants dynamiques à
  durée de vie limitée pour le rôle applicatif, rôle admin Vault dédié
  côté PostgreSQL.
- Secrets engine KV v2 pour `SESSION_SECRET`.
- Policy en lecture seule + authentification AppRole pour le backend
  (jamais le jeton racine).
- Intégration Node : récupération des secrets au démarrage, gestion du
  renouvellement/expiration des baux (`lease`).
- Démonstration réelle d'une rotation (identifiants PostgreSQL révoqués à
  expiration, backend en obtient de nouveaux).
- Secrets GitHub Actions pour la CI, séparation formelle secret
  applicatif/infra/CI (items du `ToDo.md` indépendants de Vault
  lui-même).

## Scripts

```bash
./scripts/install-vault.sh
./scripts/deploy-vault-config.sh
```

## Vérification

Exécuté (WSL2 Ubuntu 24.04) :

```text
$ ./scripts/install-vault.sh
[...]
Setting up vault (2.1.1-1) ...
Generating Vault TLS key and self-signed certificate...
[...]
Vault TLS key and self-signed certificate have been generated in '/opt/vault/tls'.
vault set on hold.
--- Vérification ---
Vault v2.1.1 (d78bbbe2d2f3d289c1ec29d431071beb23668212), built 2026-09-15T21:21:56Z
uid=995(vault) gid=987(vault) groups=987(vault)

$ ./scripts/deploy-vault-config.sh
--- Vérification ---
● vault.service - "HashiCorp Vault - A tool for managing secrets"
     Active: active (running)
     Main PID: 3664 (vault)
     CGroup: /system.slice/vault.service
             └─3664 /usr/bin/vault server -config=/etc/vault.d/vault.hcl
[...]
                 Storage: file

Key                Value
---                -----
Seal Type          shamir
Initialized        false
Sealed             true
Total Shares       0
Threshold          0
Version            2.1.1
Storage Type       file
HA Enabled         false
```

Installation et service confirmés fonctionnels : utilisateur dédié
`vault`, stockage `file` bien pris en compte, `Initialized: false` /
`Sealed: true` — exactement l'état attendu avant la prochaine étape
(initialisation + descellement).

**Observé, pas un bug** : le paquet génère de lui-même un certificat TLS
auto-signé dans `/opt/vault/tls` à l'installation (`postinst`), avant même
que notre config ne soit déployée — comportement par défaut du paquet
HashiCorp, sans rapport avec `config.hcl`. Inoffensif ici : notre listener
déployé juste après fixe explicitement `tls_disable = true`, ce certificat
reste donc inutilisé.
