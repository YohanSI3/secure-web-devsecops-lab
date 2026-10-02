# HashiCorp Vault : gestion de secrets au runtime

## Contexte

Phase 4 du `ToDo.md` : jusqu'ici, les secrets de ce lab (mot de passe
PostgreSQL, `SESSION_SECRET`) vivent dans `app/backend/.env` — jamais
commité (voir [`.gitignore`](../../app/backend/.gitignore)), mais un
simple fichier texte en clair sur disque, lu une fois au démarrage du
process. Vault répond à un problème différent de celui que gitleaks/la
push protection GitHub résolvent déjà (Phase 3) : ces outils empêchent un
secret d'**atterrir dans un dépôt Git** ; Vault s'occupe de ce qui se
passe **après**, une fois qu'un secret existe réellement quelque part — où
il est stocké, qui peut le lire, pendant combien de temps, et comment le
révoquer sans redéployer toute l'application.

Les choix concrets pour ce lab (backend installé, config, secrets
engines) sont dans [`vault/README.md`](../../vault/README.md).

## Ce qu'un `.env` ne peut pas faire

Un fichier `.env` a trois limites structurelles que Vault adresse
directement :

- **Statique** : le secret ne change que si quelqu'un (ou un script) le
  change explicitement. Pas de notion de durée de vie intégrée.
- **Aucune piste d'audit** : rien ne dit qui a lu `DATABASE_URL`, quand,
  ni depuis quel processus — le fichier est juste là, lisible par
  quiconque a accès au système de fichiers avec les bons droits Unix.
- **Révocation = redéploiement** : changer un secret compromis suppose de
  modifier le fichier *et* de redémarrer le processus qui le lit, sur
  chaque machine qui l'a — rien n'invalide activement l'ancien secret.

## Scellé/descellé (`seal`/`unseal`) : le concept central de Vault

Au repos, les données de Vault sont chiffrées avec une clé de chiffrement
elle-même protégée par un mécanisme appelé **Shamir Secret Sharing** : au
lieu d'une seule clé maîtresse stockée quelque part (point de défaillance
unique), Vault la découpe en plusieurs **clés de descellement** (`unseal
keys`), dont un certain nombre seulement (un seuil, ex. 3 sur 5) suffit à
reconstituer la clé et démarrer Vault en état utilisable (« descellé »).
Tant que Vault n'a pas reçu ce seuil de clés après un démarrage, il reste
**scellé** : les données existent sur disk mais sont illisibles, même par
un administrateur système ayant un accès root à la machine. Dans ce lab
(instance unique, pas de vraie équipe à répartir les clés), ce mécanisme a
surtout une valeur pédagogique — en production, chaque clé serait détenue
par une personne différente, aucune n'ayant seule le pouvoir de desceller
Vault seule.

## Jeton racine (`root token`) : à ne jamais utiliser au quotidien

L'initialisation de Vault produit un **jeton racine**, qui a autorité sur
tout (équivalent du rôle `postgres` superuser, ou de `root` sur un
système Linux). Comme ces deux précédents, jamais utilisé par
l'application elle-même — réservé à la configuration initiale (activer des
secrets engines, écrire des policies). Voir
[`vault/README.md`](../../vault/README.md) pour le mécanisme
d'authentification réellement utilisé par le backend (AppRole).

## Secrets statiques vs secrets dynamiques

Vault distingue deux familles de "secrets engines" :

- **statiques (KV)** : Vault stocke une valeur telle quelle (chiffrée),
  comme un coffre-fort — utile pour un secret qui n'a pas de "propriétaire"
  côté infrastructure capable de le générer/révoquer à la demande (ex.
  `SESSION_SECRET`, une valeur arbitraire choisie une fois).
- **dynamiques** : Vault **génère lui-même** le secret à la demande, avec
  une durée de vie limitée (`TTL`/`lease`), et sait le **révoquer**
  activement à expiration (ou sur demande) en agissant directement sur le
  système cible. Pour PostgreSQL : Vault crée un rôle PostgreSQL éphémère
  avec les permissions voulues, le détruit automatiquement à expiration du
  bail — personne (pas même l'opérateur humain) n'a besoin de connaître
  un mot de passe applicatif permanent.

Ce lab utilise les deux : KV pour `SESSION_SECRET`, dynamique pour les
identifiants PostgreSQL du backend — voir
[`vault/README.md`](../../vault/README.md) pour le détail.

## Comment un secrets engine dynamique génère réellement un secret

Vault ne sait rien de PostgreSQL par magie : un plugin dédié (ici
`postgresql-database-plugin`) relie le moteur `database` générique à un
système cible précis. Trois éléments définissent ce qu'il fait,
configurés une fois par un opérateur (jamais par l'application elle-même) :

- **Une connexion admin** vers le système cible (voir
  [`vault/README.md`](../../vault/README.md) — un rôle PostgreSQL dédié,
  capable de créer/détruire des rôles, jamais utilisé directement par
  l'application).
- **Des instructions de création/révocation **templatisées**, écrites en
  SQL natif du système cible — Vault ne "connaît" pas PostgreSQL au-delà
  d'exécuter ce SQL via la connexion admin, avec des gabarits
  (`{{name}}`, `{{password}}`, `{{expiration}}`) que Vault remplit à
  chaque émission avec des valeurs générées aléatoirement.
- **Une durée de vie** (`default_ttl` : durée par défaut d'un bail,
  `max_ttl` : plafond même avec renouvellements) — c'est elle qui rend le
  secret "dynamique" plutôt qu'un simple générateur de mots de passe
  one-shot : passé ce délai, Vault exécute lui-même l'instruction de
  révocation, sans action humaine.

Chaque fois qu'un client demande un identifiant
(`vault read database/creds/<rôle>`), Vault exécute la création
templatisée avec de nouvelles valeurs et retourne un **bail** (`lease`) —
un identifiant qui référence ce secret précis, utilisé pour le
renouveler ou le révoquer explicitement avant son expiration naturelle
(`vault lease revoke <lease_id>`). La révocation n'est pas symbolique :
elle exécute réellement l'instruction de révocation définie (typiquement
`DROP ROLE` pour PostgreSQL) sur le système cible — après quoi
l'identifiant n'existe plus du tout, pas seulement "n'est plus reconnu
par Vault".

## Shamir Secret Sharing en détail : pourquoi 3 clés sur 5 suffisent

Question naturelle en pratiquant le descellement pour la première fois :
si 5 clés ont été générées, pourquoi 3 seulement suffisent-elles à
reconstituer la clé maîtresse — un simple hasard d'implémentation, ou
une propriété voulue de l'algorithme ?

**C'est une propriété voulue, au cœur même du schéma de Shamir.** L'idée
(publiée par Adi Shamir en 1979) : découper un secret en `n` parts de
telle sorte qu'un **seuil** `k` de parts (`k` ≤ `n`, choisi à l'avance —
ici `k=3`, `n=5`) suffise à reconstituer le secret, mais que `k-1` parts
ou moins ne révèlent **strictement aucune information** sur le secret,
pas même partielle. Concrètement, Shamir construit un polynôme aléatoire
de degré `k-1` dont le terme constant *est* le secret, puis distribue `n`
points distincts de ce polynôme comme parts : mathématiquement, il faut
exactement `k` points pour déterminer de façon unique un polynôme de
degré `k-1` (interpolation de Lagrange) — avec seulement `k-1` points,
une infinité de polynômes de ce degré passent par ces points, un
attaquant n'apprend donc rien sur le terme constant qu'il cherche.

Pourquoi avoir `n=5` plutôt que de fixer directement `n=k=3` ? Pour la
**tolérance à la perte** : avec 5 parts dont 3 nécessaires, jusqu'à 2
parts peuvent être perdues (clé égarée, personne partie de l'équipe) sans
rendre Vault définitivement inutilisable — un compromis classique entre
robustesse (perdre quelques parts ne bloque rien) et sécurité (il faut
quand même qu'une majorité significative de détenteurs de clés coopère,
pas une seule personne). Le seuil `k` et le total `n` sont choisis
librement à l'initialisation (`-key-shares`/`-key-threshold`) selon le
nombre de personnes de confiance réellement disponibles dans une
organisation donnée.

## `rekey` et `generate-root` : les deux cérémonies d'urgence

Deux opérations Vault, toutes deux pensées pour un scénario de
compromission (ou simplement pour renouveler périodiquement le matériel
sensible) :

- **`vault operator rekey`** — génère un **nouveau** jeu de clés de
  descellement (nouveau `n`/`k` possible), invalidant immédiatement
  l'ancien. Nécessite de fournir le **seuil actuel** de clés *existantes*
  pour autoriser l'opération — cohérent avec le modèle de confiance
  global : changer les clés de confiance exige déjà la confiance d'un
  quorum de détenteurs actuels, pas d'une seule personne.
- **`vault operator generate-root`** — émet un **nouveau** jeton racine,
  sans jamais avoir besoin de l'ancien (utile si justement l'ancien est
  compromis ou perdu). Nécessite elle aussi un quorum de clés de
  descellement, mais ajoute une étape supplémentaire : le nouveau jeton
  n'est jamais transmis en clair sur le réseau/dans la sortie de chaque
  participant. Chaque détenteur de clé fournit la sienne, ce qui fait
  progresser un **"Encoded Token"** chiffré avec un **OTP** (one-time pad)
  généré au lancement de la cérémonie ; seule la personne qui a lancé
  `generate-root -init` (et donc possède l'OTP) peut **décoder**
  localement ce jeton final (`generate-root -decode`) — les autres
  détenteurs de clés participent à l'autoriser sans jamais voir le jeton
  résultant lui-même.

L'ancien jeton racine n'est pas automatiquement invalidé par
`generate-root` : il faut le révoquer explicitement
(`vault token revoke <ancien-jeton>`), typiquement en s'authentifiant
avec le nouveau. Voir [`vault/README.md`](../../vault/README.md) pour le
cas réel rencontré dans ce lab qui a rendu cette révocation nécessaire.
