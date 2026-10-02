# HashiCorp Vault — documentation technique

Phase 4 du `ToDo.md` : gestion des secrets applicatifs réels (mot de
passe PostgreSQL, `SESSION_SECRET`) au runtime, au-delà de leur simple
non-commit (déjà couvert par gitleaks/push protection, Phase 3). Pour le
fonctionnement général de Vault (scellé/descellé, jeton racine, secrets
statiques vs dynamiques), voir [`Notes/vault/`](../Notes/vault/README.md).

## État actuel

Installé, configuré, initialisé et descellé — jeu de clés de descellement
et jeton racine déjà renouvelés une fois (voir « Bug réel » plus bas).
Secrets engine KV v2 activé, `SESSION_SECRET` migré depuis
`app/backend/.env` (voir « KV v2 : `SESSION_SECRET` » plus bas). Secrets
engine `database` (identifiants PostgreSQL dynamiques), AppRole et
intégration Node encore à faire — voir « Reste à faire » plus bas.

## KV v2 : `SESSION_SECRET`

[`scripts/setup-vault-kv.sh`](../scripts/setup-vault-kv.sh) active le
moteur KV v2 au chemin `secret/` et y migre la valeur déjà présente dans
`app/backend/.env` (pas de régénération : migrer un secret déjà en usage,
pas en créer un nouveau).

Exécuté :

```text
$ ./scripts/setup-vault-kv.sh
Success! Enabled the kv-v2 secrets engine at: secret/
=========== Secret Path ===========
secret/data/secure-web-lab/backend
--- Vérification (clés présentes, pas les valeurs) ---
"SESSION_SECRET":
```

Confirme le moteur actif et le secret présent, sans jamais afficher sa
valeur (script conçu pour n'extraire que les noms de clé du JSON retourné
par `vault kv get`, jamais les valeurs — voir
[`scripts/setup-vault-kv.sh`](../scripts/setup-vault-kv.sh)).

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

## Secrets engine `database` : identifiants PostgreSQL dynamiques

[`scripts/setup-vault-postgresql-engine.sh`](../scripts/setup-vault-postgresql-engine.sh) :

- Crée le rôle PostgreSQL `vault_admin` (`CREATEROLE`, membre de
  `secure_web_lab_app` avec `ADMIN OPTION` — peut accorder cette
  appartenance à d'autres rôles sans être `SUPERUSER`).
- Configure la connexion Vault → PostgreSQL
  (`database/config/secure-web-lab`) avec ce rôle.
- Définit un rôle Vault (`database/roles/secure-web-lab-app`) dont
  l'instruction de création (`creation_statements`) fait `CREATE ROLE
  "{{name}}" ... IN ROLE secure_web_lab_app` — le rôle dynamique hérite
  des privilèges de `secure_web_lab_app` par simple appartenance, sans
  `GRANT` supplémentaire à répéter par identifiant émis. `VALID UNTIL
  '{{expiration}}'` ceinture-et-bretelles côté PostgreSQL lui-même (le
  SGBD refuse une connexion expirée indépendamment de Vault).
  `default_ttl=1h`/`max_ttl=24h`.

### `pg_hba.conf` : `+secure_web_lab_app` plutôt qu'un nom de rôle fixe

Problème direct avec le resserrement fait plus tôt dans cette phase
([`postgresql/README.md`](../postgresql/README.md)) : la règle
`host secure_web_lab secure_web_lab_app 127.0.0.1/32 ...` ne matche que ce
nom de rôle exact, alors que Vault génère un nom différent à chaque
identifiant dynamique (ex. `v-root-secure-w-...-<timestamp>`) —
impossible à lister à l'avance. Remplacé par
`host secure_web_lab +secure_web_lab_app 127.0.0.1/32 ...` dans
[`pg_hba.conf`](pg_hba.conf) : le préfixe `+` fait matcher non pas un nom
de rôle précis mais **l'appartenance** à ce rôle — couvre à la fois
`secure_web_lab_app` lui-même (un rôle est membre de lui-même) et tout
rôle dynamique créé `IN ROLE secure_web_lab_app`, sans jamais élargir
l'accès au-delà de ce qui en hérite réellement. Ligne séparée ajoutée pour
`vault_admin` (connexion propre à Vault, jamais réutilisée par
l'application).

Vérifié sans régression après redéploiement (`/health` toujours
`{"status":"ok","db":"ok"}` avec le rôle statique `secure_web_lab_app`
inchangé) avant de passer au test des identifiants dynamiques.

### Vérification : émission, usage réel, puis révocation réelle

```text
$ ./scripts/setup-vault-postgresql-engine.sh
CREATE ROLE
GRANT ROLE
Success! Enabled the database secrets engine at: database/
Success! Data written to: database/config/secure-web-lab
Success! Data written to: database/roles/secure-web-lab-app
lease_id           database/creds/secure-web-lab-app/uqDT7m1dCQKso4HqS3LLVjk6
lease_duration     1h
username           v-root-secure-w-QLV6C2JUTTSwZrSCe1yz-1790960926

$ psql -h 127.0.0.1 -U v-root-secure-w-QLV6C2JUTTSwZrSCe1yz-1790960926 -d secure_web_lab -c "SELECT current_user, session_user;"
                  current_user                   |                  session_user
-------------------------------------------------+-------------------------------------------------
 v-root-secure-w-QLV6C2JUTTSwZrSCe1yz-1790960926 | v-root-secure-w-QLV6C2JUTTSwZrSCe1yz-1790960926
(1 row)

$ vault lease revoke database/creds/secure-web-lab-app/uqDT7m1dCQKso4HqS3LLVjk6
All revocation operations queued successfully!

$ sudo -u postgres psql -c "SELECT rolname FROM pg_roles WHERE rolname = 'v-root-secure-w-QLV6C2JUTTSwZrSCe1yz-1790960926';"
 rolname
---------
(0 rows)

$ psql -h 127.0.0.1 -U v-root-secure-w-QLV6C2JUTTSwZrSCe1yz-1790960926 -d secure_web_lab -c "SELECT 1;"
psql: error: connection to server at "127.0.0.1", port 5432 failed: FATAL:  no pg_hba.conf entry for host "127.0.0.1", user "v-root-secure-w-QLV6C2JUTTSwZrSCe1yz-1790960926", database "secure_web_lab", SSL encryption
```

**Rotation réelle confirmée de bout en bout**, pas seulement documentée :
identifiant émis à la demande, accès effectivement équivalent à
`secure_web_lab_app` (`current_user` le confirme), puis `vault lease
revoke` a réellement exécuté `DROP ROLE` côté PostgreSQL (`0 rows`, pas
juste une expiration comptable côté Vault) — l'ancien identifiant est
désormais aussi inutilisable qu'un rôle qui n'a jamais existé.

**Observé, pas un bug** : une fois le rôle supprimé, l'échec de connexion
affiche `no pg_hba.conf entry` plutôt qu'un échec d'authentification
classique. PostgreSQL évalue `pg_hba.conf` avant de vérifier le mot de
passe ; pour une règle `+secure_web_lab_app`, il doit d'abord résoudre
l'appartenance au groupe du rôle qui se connecte — impossible pour un rôle
qui n'existe plus du tout, d'où ce message plutôt qu'un rejet de mot de
passe. Comportement cohérent, juste un message différent de celui qu'on
pourrait intuitivement attendre pour un rôle "supprimé".

**Détail à noter pour l'étape suivante (AppRole)** : le nom généré,
`v-root-secure-w-...`, inclut `root` parce que l'émission a été demandée
avec le jeton racine (Vault inclut le nom d'affichage du jeton appelant
dans le nom du rôle dynamique). Une fois le backend authentifié via
AppRole plutôt que le jeton racine, ce préfixe changera en conséquence —
signal visible, dans les noms de rôle PostgreSQL eux-mêmes, de qui a
réellement demandé chaque identifiant.

## Reste à faire

- Policy en lecture seule + authentification AppRole pour le backend
  (jamais le jeton racine au quotidien).
- Intégration Node : récupération des secrets au démarrage (KV +
  identifiants PostgreSQL dynamiques), gestion du renouvellement/
  expiration des baux (`lease`) pendant que le process tourne.
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
