# PostgreSQL — documentation technique

Durcissement concret de l'instance PostgreSQL de ce lab, dans le même
esprit que le travail fait sur Nginx/OS en Phase 2 — un service réseau de
plus à sécuriser, pas seulement Nginx. Pour le fonctionnement général de
PostgreSQL (modèle de rôles, `pg_hba.conf`), voir
[`Notes/postgresql/`](../Notes/postgresql/README.md). Pour la création du
rôle/de la base applicatifs (déjà faite, Phase 5), voir
[`app/backend/README.md`](../app/backend/README.md#connexion-à-la-base--rôle-dédié-pas-superuser).

## État avant durcissement

Installation par défaut Ubuntu 24.04 (PostgreSQL 16, voir
[`scripts/install-postgresql.sh`](../scripts/install-postgresql.sh)),
vérifiée en conditions réelles plutôt que supposée :

- `listen_addresses = localhost`, `password_encryption = scram-sha-256` —
  déjà corrects par défaut, rien à changer.
- `pg_hba.conf` au défaut Debian/Ubuntu : `host all all 127.0.0.1/32
  scram-sha-256` (et `::1/128`) — autorise **n'importe quel rôle
  PostgreSQL à se connecter à n'importe quelle base** depuis la boucle
  locale, plus des lignes `replication` jamais utilisées dans ce lab
  (instance unique, pas de réplica).
- Aucun `log_connections`/`log_disconnections`, aucun timeout par rôle.

## Privilèges base : `REVOKE CONNECT ... FROM PUBLIC`

Par défaut, PostgreSQL accorde `CONNECT` sur chaque base à `PUBLIC`
(tous les rôles). [`scripts/harden-postgresql.sh`](../scripts/harden-postgresql.sh)
retire ce droit par défaut puis le redonne explicitement au seul rôle
applicatif :

```sql
REVOKE CONNECT ON DATABASE secure_web_lab FROM PUBLIC;
GRANT CONNECT ON DATABASE secure_web_lab TO secure_web_lab_app;
```

Sans effet sur `secure_web_lab_app` lui-même : le **propriétaire** d'une
base PostgreSQL conserve toujours le droit de s'y connecter,
indépendamment des `GRANT`/`REVOKE` (une des rares exceptions au système
de permissions classique). L'effet réel : si un futur rôle PostgreSQL est
créé sur ce cluster (ex. pour un autre projet partageant la même
instance), il ne pourra pas se connecter à `secure_web_lab` sans un
`GRANT` explicite — moins de surface d'accès par défaut, même logique que
le rôle applicatif sans `SUPERUSER`/`CREATEDB`/`CREATEROLE`.

## `pg_hba.conf` : restreint au rôle et à la base précis

[`pg_hba.conf`](pg_hba.conf) (ce dépôt) remplace le défaut Ubuntu, déployé
par [`scripts/deploy-postgresql-hba.sh`](../scripts/deploy-postgresql-hba.sh) :

| Avant (défaut Ubuntu) | Après (ce lab) |
|---|---|
| `host all all 127.0.0.1/32 scram-sha-256` | `host secure_web_lab secure_web_lab_app 127.0.0.1/32 scram-sha-256` |
| `host replication all 127.0.0.1/32 scram-sha-256` | *(retiré)* |
| `local all all peer` | *(conservé — administration locale uniquement)* |

- **Base et rôle explicites plutôt que `all all`** : même sans compte
  PostgreSQL compromis, limite ce qu'une connexion TCP peut même
  *tenter* d'atteindre — un rôle PostgreSQL mal configuré par erreur à
  l'avenir sur ce cluster ne pourrait pas se connecter à
  `secure_web_lab` même avec le bon mot de passe, tant qu'aucune ligne
  `pg_hba.conf` ne l'autorise explicitement.
- **Lignes `replication` retirées** : aucune réplication configurée dans
  ce lab (instance unique) — une méthode d'authentification active pour
  une fonctionnalité jamais utilisée est juste de la surface d'attaque
  gratuite, pas un comportement standard à préserver (contrairement au
  choix fait côté HTTP en Phase 2 de ne pas retirer de méthodes standard
  pour "durcir" un site qui doit rester réaliste — ici il s'agit d'une
  fonctionnalité serveur jamais activée, pas d'un comportement client
  normal à simuler).
- **Administration via `peer` uniquement** : `sudo -u postgres psql`
  reste la seule voie d'administration, cohérent avec l'absence totale de
  règle TCP pour le rôle `postgres` — un outil GUI (pgAdmin, DBeaver) qui
  voudrait se connecter en TCP avec le rôle `postgres` ne le pourrait pas
  avec cette config ; à ajouter explicitement le jour où ce besoin existe
  réellement (même logique que SSH non ouvert par défaut dans
  [`firewall/README.md`](../firewall/README.md#délibérément-non-ouvert--ssh-22tcp)).

## Timeouts par rôle applicatif

```sql
ALTER ROLE secure_web_lab_app SET statement_timeout = '15s';
ALTER ROLE secure_web_lab_app SET idle_in_transaction_session_timeout = '30s';
```

Équivalent côté base de données des timeouts Nginx de Phase 2 : une
requête ou une transaction qui ne devrait normalement durer que quelques
millisecondes (CRUD simple sur `users`/`audit_log`) ne doit jamais pouvoir
bloquer indéfiniment une connexion ni retenir des verrous. Portée
volontairement limitée au **rôle applicatif** (`SET` sur le rôle, pas
`ALTER SYSTEM`) : une session d'administration via `postgres` (migration
manuelle longue, par exemple) n'est pas affectée — même principe que le
rate limiting Nginx appliqué seulement aux routes concernées, pas au site
entier.

Ces réglages ne s'appliquent qu'aux **nouvelles** connexions ouvertes
après le changement : un redémarrage du backend Node (qui gère un pool de
connexions) est nécessaire pour que ses connexions existantes en
bénéficient.

## Journalisation : connexions, déconnexions, hôte distant

```sql
ALTER SYSTEM SET log_connections = 'on';
ALTER SYSTEM SET log_disconnections = 'on';
ALTER SYSTEM SET log_line_prefix = '%m [%p] %q%u@%d %h ';
```

Par défaut, seules les authentifications **échouées** sont journalisées
(inconditionnel, pas besoin de `log_connections`) ; `log_connections`/
`log_disconnections` ajoutent la trace des connexions et déconnexions
**réussies** — parité avec l'audit applicatif déjà en place
([`app/backend/README.md`](../app/backend/README.md#audit-srcauditjs)),
cette fois au niveau du service de base de données lui-même, pas
seulement des actions métier. `%h` ajouté au `log_line_prefix` par défaut
(qui ne contenait que `%m [%p] %q%u@%d `) : expose l'hôte distant de
chaque connexion dans les logs — prérequis pour qu'un outil comme
fail2ban (déjà en place côté Nginx, voir
[`Notes/fail2ban/`](../Notes/fail2ban/README.md)) puisse un jour extraire
une IP à bannir depuis les logs PostgreSQL (évolution envisagée, pas
encore faite — voir section suivante).

## TLS : pas activé pour la connexion Node → PostgreSQL, et pourquoi

`ssl = on` au niveau serveur (valeur par défaut Ubuntu, certificat
auto-signé `ssl-cert-snakeoil` fourni par le paquet), mais rien ne
l'impose dans `pg_hba.conf` (pas de règle `hostssl`) : la connexion
Node → PostgreSQL reste en clair sur `127.0.0.1`. Décision délibérée, pas
un oubli — même raisonnement que la connexion Nginx → Node déjà documentée
([`app/backend/README.md`](../app/backend/README.md#127001-uniquement-jamais-0000)) :
aucune des deux extrémités ne quitte la machine locale, donc pas de
réseau physique sur lequel un tiers pourrait intercepter le trafic en
clair. Imposer `hostssl` ici ajouterait de la complexité (certificat à
gérer côté client `pg`, `sslmode` à configurer) sans réduire de risque
réel tant que les deux processus restent sur `127.0.0.1` — à revoir si
PostgreSQL et le backend venaient un jour à tourner sur des machines
séparées.

## Logs : rotation

Le paquet `postgresql-common` d'Ubuntu installe déjà
`/etc/logrotate.d/postgresql-common` à l'installation — contrairement à
Nginx en Phase 2 (où la rotation a dû être mise en place à la main), rien
à faire ici : à vérifier une fois (`cat /etc/logrotate.d/postgresql-common`)
plutôt qu'à reconstruire une rotation déjà fournie par le paquet.

## fail2ban : jail dédiée aux échecs d'authentification

L'infrastructure fail2ban déjà en place (Phase 2, côté Nginx) a été
étendue avec une jail `postgresql-auth`, qui dépend justement du `%h`
ajouté ci-dessus à `log_line_prefix` — voir
[`fail2ban/README.md#postgresql-auth--étend-fail2ban-à-un-service-non-http`](../fail2ban/README.md#postgresql-auth--étend-fail2ban-à-un-service-non-http)
pour le détail (filtre, portée réelle limitée vu que PostgreSQL n'est
jamais exposé au-delà de `127.0.0.1`).

## Scripts

```bash
./scripts/harden-postgresql.sh       # privilèges base, timeouts, journalisation
./scripts/deploy-postgresql-hba.sh   # déploie postgresql/pg_hba.conf
```

Les deux sont idempotents (rejouables sans effet de bord différent).

## Vérification

Exécuté (WSL2 Ubuntu 24.04, PostgreSQL 16) :

```text
$ ./scripts/harden-postgresql.sh
--- Privilèges base : retire l'accès par défaut à PUBLIC ---
REVOKE
GRANT
--- Timeouts par rôle applicatif ---
ALTER ROLE
ALTER ROLE
--- Journalisation : connexions, déconnexions, hôte distant ---
ALTER SYSTEM
ALTER SYSTEM
ALTER SYSTEM
 pg_reload_conf
----------------
 t
(1 row)

--- Vérification ---
      rolname       |                            rolconfig
--------------------+-----------------------------------------------------------------
 secure_web_lab_app | {statement_timeout=15s,idle_in_transaction_session_timeout=30s}
(1 row)

 log_connections
-----------------
 on
(1 row)

 log_disconnections
--------------------
 on
(1 row)

   log_line_prefix
---------------------
 %m [%p] %q%u@%d %h
(1 row)

$ ./scripts/deploy-postgresql-hba.sh
--- Vérification ---
 pg_reload_conf
----------------
 t
(1 row)

local   all             postgres                                peer
local   all             all                                     peer
host    secure_web_lab  secure_web_lab_app      127.0.0.1/32    scram-sha-256
host    secure_web_lab  secure_web_lab_app      ::1/128         scram-sha-256

$ cat /etc/logrotate.d/postgresql-common
/var/log/postgresql/*.log {
       weekly
       rotate 10
       copytruncate
       delaycompress
       compress
       notifempty
       missingok
       su root root
}

# Backend redémarré pour que le pool de connexions reprenne avec les
# nouveaux réglages de rôle :
$ curl -s http://127.0.0.1:3000/health
{"status":"ok","db":"ok"}

# Test négatif : confirme que le resserrement de pg_hba.conf bloque bien
# un accès auparavant permis (postgres en TCP n'a plus aucune règle) :
$ PGPASSWORD=wrongpass psql -h 127.0.0.1 -U postgres -d secure_web_lab -c "SELECT 1;"
psql: error: connection to server at "127.0.0.1", port 5432 failed: FATAL:  no pg_hba.conf entry for host "127.0.0.1", user "postgres", database "secure_web_lab", SSL encryption
connection to server at "127.0.0.1", port 5432 failed: FATAL:  no pg_hba.conf entry for host "127.0.0.1", user "postgres", database "secure_web_lab", no encryption

# Confirme que les timeouts par rôle sont bien appliqués au rôle
# applicatif réel (pas seulement visibles dans pg_roles) :
$ PGPASSWORD="$APP_PASS" psql -h 127.0.0.1 -U secure_web_lab_app -d secure_web_lab \
    -c "SHOW statement_timeout; SHOW idle_in_transaction_session_timeout;"
 statement_timeout
-------------------
 15s
(1 row)

 idle_in_transaction_session_timeout
-------------------------------------
 30s
(1 row)
```

**Durcissement confirmé de bout en bout** : privilèges base restreints
(`REVOKE`/`GRANT` effectifs), `pg_hba.conf` resserré et vérifié par un
test négatif réel (accès auparavant permis maintenant refusé), timeouts
appliqués au rôle applicatif réel (pas seulement déclarés), journalisation
des connexions activée, rotation déjà gérée par le paquet Debian, backend
toujours fonctionnel après redémarrage.
