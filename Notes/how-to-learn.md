# Comment lire ce dossier

`Notes/` contient le cours que ce projet se donne à lui-même (voir
[`README.md`](README.md) pour la convention d'écriture). Ce fichier
propose un **ordre de lecture** — chaque sujet s'appuie sur les
précédents, lire dans le désordre laisse des trous (ex. comprendre les
secrets dynamiques de Vault sans connaître d'abord le modèle de rôles
PostgreSQL, ou lire le RBAC applicatif sans avoir vu ce qu'IAM recouvre
en général).

Pour chaque entrée : ce que le sujet apprend en résumé, et pourquoi ça
vaut la peine de le savoir — pas seulement pour ce projet, mais comme
connaissance transférable.

L'ordre suit globalement les phases du `ToDo.md`, avec deux écarts
délibérés signalés en cours de route (Git et Vault), placés là où ils
sont le plus utiles à comprendre plutôt que là où ils apparaissent
chronologiquement dans le plan.

## 0. Avant tout : comment ce dossier est organisé

- [`README.md`](README.md) — la distinction centrale de tout le projet :
  `Notes/` explique un concept en général, la documentation technique
  co-localisée (ex. `nginx/README.md`) explique le choix fait *ici*.
  Comprendre cette séparation avant de lire la suite évite de confondre
  "comment ça marche" et "ce qu'on a choisi".

## 1. Nginx — les bases (Phase 1)

- [`nginx/installation/`](nginx/installation/README.md) — pourquoi
  installer depuis les dépôts officiels Ubuntu plutôt qu'un PPA tiers, et
  le modèle de privilèges par défaut d'Nginx (processus master root,
  workers sous un utilisateur dédié). Point de départ : comprendre
  *qui* exécute réellement le serveur web avant de le durcir.
- [`nginx/configuration/`](nginx/configuration/README.md) (4 fichiers) —
  comment une config versionnée dans un dépôt Git se relie à
  `/etc/nginx/` (symlinks, `sites-available`/`sites-enabled`), le modèle
  de permissions d'un webroot, et le rôle de chaque directive d'un
  server block. Utile dès qu'on doit lire ou écrire une config Nginx
  n'importe où, pas seulement ici.
- [`nginx/environnements/`](nginx/environnements/README.md) (3 fichiers)
  — simuler dev/staging/prod sur une seule machine avec plusieurs vhosts
  distincts. Utile pour comprendre une stratégie de séparation
  d'environnements quand on n'a pas (encore) plusieurs serveurs.
- [`nginx/tls/`](nginx/tls/README.md) (6 fichiers) — qu'est-ce qu'une CA,
  pourquoi en créer une localement, génération de certificats,
  permissions de déploiement, et deux pièges réels (fusion de
  `ssl_protocols`, durcissement des suites/OCSP/reprise de session).
  Le sujet le plus dense de Phase 1 — comprendre TLS correctement est un
  prérequis pour à peu près tout le reste (HSTS, cookies `secure`,
  Vault...).
- [`nginx/headers-securite/`](nginx/headers-securite/README.md)
  (3 fichiers) — ce que chaque en-tête HTTP de sécurité empêche
  concrètement, et pourquoi centraliser cette config plutôt que la
  répéter.
- [`nginx/divulgation-version/`](nginx/divulgation-version/README.md) —
  pourquoi masquer la version exacte d'un logiciel exposé (lien direct
  avec le cycle CVE/reconnaissance), et les différents niveaux de fuite
  possibles au-delà du simple `Server:` header.

## 2. Durcissement système et réseau (Phase 2)

- [`nginx/utilisateur-dedie/`](nginx/utilisateur-dedie/README.md)
  (3 fichiers) — pourquoi remplacer l'utilisateur partagé `www-data` par
  un compte de service dédié à une seule application. **Le principe le
  plus réutilisé de tout le projet** : on le retrouve ensuite identique
  pour le rôle PostgreSQL applicatif, puis pour `vault_admin` — comprendre
  ce premier cas suffit à comprendre les deux autres.
- [`ufw/`](ufw/README.md) (3 fichiers) — netfilter/iptables/ufw, la
  politique par défaut (*default-deny*), et une limite réelle découverte
  sous WSL2 (la portée du filtrage ne couvre pas l'hôte Windows). Utile
  pour situer ufw dans la pile réseau Linux plutôt que le traiter comme
  une boîte noire.
- [`fail2ban/`](fail2ban/README.md) (2 fichiers) — la différence entre
  détection *a priori* (firewall, rate limiting) et réaction *a
  posteriori* à un motif dans des logs déjà écrits ; ce que fail2ban ne
  voit structurellement jamais. Mécanique volontairement générique
  (filtre + fichier de log + seuil) : réutilisée plus tard dans le projet
  pour un service entièrement différent (PostgreSQL), preuve que le
  concept n'est pas spécifique à Nginx.
- [`nginx/rate-limiting/`](nginx/rate-limiting/README.md) — protection
  au moment même de la requête, par débit, indépendamment de tout succès
  ou échec (complémentaire de fail2ban, pas redondant).
- [`nginx/controle-tailles-requetes/`](nginx/controle-tailles-requetes/README.md)
  — même objectif que le rate limiting (protéger la capacité du serveur)
  mais sur une dimension différente : la taille plutôt que le débit.
- [`nginx/timeouts/`](nginx/timeouts/README.md) — pourquoi les délais par
  défaut d'Nginx sont pensés pour la tolérance, pas pour limiter
  l'exposition à un client anormalement lent.
- [`nginx/journalisation/`](nginx/journalisation/README.md) — le
  *contenu* d'une ligne de log, pas sa gestion de fichier ; pourquoi le
  format par défaut ne suffit plus une fois plusieurs mécanismes de rejet
  actifs.
- [`nginx/rotation-logs/`](nginx/rotation-logs/README.md) — le rôle de
  `logrotate`, exécuté par un timer systemd indépendant du service qu'il
  surveille — distinction importante entre "qui écrit un log" et "qui le
  fait tourner".

## 3. Un aparté nécessaire : Git lui-même

- [`git/`](git/README.md) — les fins de ligne CRLF/LF, découvert en
  travaillant entre Windows et WSL2. Placé ici (pas en Phase 1, où le
  dépôt a été créé) parce que c'est en écrivant les scripts bash de la
  Phase 2 que le problème est devenu concret (un script qui casse parce
  qu'une ligne se termine par `\r\n`). Utile dès qu'un projet traverse
  plusieurs systèmes d'exploitation, bien au-delà de ce lab.

## 4. DevSecOps / CI (Phase 3)

- [`devsecops/README.md`](devsecops/README.md) — le principe organisateur
  du domaine, *shift left* : plus un problème de sécurité est détecté
  tard dans le cycle de développement, plus il coûte cher à corriger.
  Lire ce fichier avant les quatre suivants, il donne le fil conducteur.
- [`devsecops/sast-dast-sca.md`](devsecops/sast-dast-sca.md) — les
  grandes catégories de scan de sécurité (SAST, DAST, SCA, IAST), ce que
  chacune trouve et ne trouve structurellement pas.
- [`devsecops/secrets-scanning.md`](devsecops/secrets-scanning.md) —
  comment un scanner de secrets détecte quelque chose (regex vs entropie)
  et pourquoi scanner *avant* un commit (push protection) vaut mieux que
  scanner après.
- [`devsecops/branches-protegees-et-ci-gate.md`](devsecops/branches-protegees-et-ci-gate.md)
  — modèles de protection de branche ; pourquoi une CI qui ne bloque rien
  n'est qu'un tableau de bord décoratif.
- [`devsecops/paysage-outillage.md`](devsecops/paysage-outillage.md) —
  tableau de correspondance outil gratuit déployé ici / équivalent
  commercial de référence, pour se repérer dans l'industrie sans dépendre
  d'une licence payante dans ce lab.

## 5. Construire une vraie application (fondations de Phase 5)

- [`nodejs/README.md`](nodejs/README.md) — l'écosystème Node.js/npm, et
  pourquoi ce projet s'autorise ici un dépôt tiers (NodeSource) alors que
  le principe "dépôts Ubuntu uniquement" avait été posé pour Nginx — un
  runtime applicatif évolue à un rythme que le cycle d'une distribution
  LTS ne peut pas suivre.
- [`postgresql/README.md`](postgresql/README.md) — le modèle de rôles
  PostgreSQL (pas de distinction utilisateur/groupe), `pg_hba.conf` et
  l'ordre d'évaluation de ses règles, le système `GRANT`/`REVOKE` et
  l'exception du propriétaire, l'appartenance de rôle et la
  correspondance par groupe (`+role`). **Prérequis direct pour la
  section Vault plus bas** — les identifiants PostgreSQL dynamiques n'ont
  de sens qu'une fois ce modèle compris.

## 6. IAM — authentification et autorisation (Phase 5)

- [`iam/README.md`](iam/README.md) — la distinction entre identification,
  authentification et autorisation : trois questions indépendantes,
  souvent confondues à tort.
- [`iam/mots-de-passe.md`](iam/mots-de-passe.md) — hachage, coût bcrypt,
  et pourquoi la longueur prime sur la complexité imposée (recommandation
  NIST actuelle).
- [`iam/sessions-vs-jwt.md`](iam/sessions-vs-jwt.md) — les deux grands
  modèles de maintien d'authentification entre deux requêtes, et le
  compromis central révocation immédiate vs absence d'état côté serveur.
- [`iam/rbac-et-enumeration.md`](iam/rbac-et-enumeration.md) — contrôle
  d'accès par rôle, résistance à l'énumération de comptes, fixation de
  session.
- [`iam/reinitialisation-mot-de-passe.md`](iam/reinitialisation-mot-de-passe.md)
  — conception d'un jeton de réinitialisation à usage unique (entropie,
  hachage, durée de vie courte) et pourquoi un reset réussi doit couper
  les sessions actives existantes.

## 7. Séparer et gérer les secrets (Phase 4 — volontairement lu en dernier)

Écart déliberé par rapport au numéro de phase du `ToDo.md` : cette
section dépend de deux choses vues plus haut (le modèle de rôles
PostgreSQL, et l'existence de vrais secrets applicatifs une fois IAM
construit) — la lire avant aurait laissé les exemples abstraits.

- [`devsecops/separation-secrets.md`](devsecops/separation-secrets.md) —
  pourquoi isoler les secrets applicatifs, d'infrastructure et de CI dans
  des magasins distincts plutôt qu'un coffre unique : le raisonnement par
  *rayon d'explosion* (une fuite dans un contexte ne doit jamais donner
  accès aux deux autres).
- [`vault/README.md`](vault/README.md) — ce qu'un simple fichier `.env`
  ne peut structurellement pas faire (pas de durée de vie, pas de piste
  d'audit, révocation = redéploiement manuel) ; le mécanisme de
  scellement/descellement et le partage de secret de Shamir (pourquoi un
  seuil de clés suffit sans jamais exposer le secret complet) ; la
  différence entre secrets statiques et secrets **dynamiques** (générés
  à la demande, à durée de vie limitée, révocables activement) ; policies
  et authentification AppRole (`role_id`/`secret_id`, comparable à une
  identité de machine plutôt qu'à un accès permanent) ; les cérémonies
  `rekey`/`generate-root` pour un vrai scénario de compromission. Le
  sujet le plus avancé du projet — n'a de sens qu'avec PostgreSQL et IAM
  déjà compris.
