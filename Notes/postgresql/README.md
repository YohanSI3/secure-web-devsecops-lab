# PostgreSQL

## Contexte

Phase 5 du `ToDo.md` (IAM) : stockage des utilisateurs, mots de passe
hachés, sessions et permissions. Cours général sur le modèle de rôles
PostgreSQL ; les choix concrets (nom du rôle, de la base, permissions
exactes) sont dans
[`app/backend/README.md`](../../app/backend/README.md).

## Rôles : pas de distinction "utilisateur" vs "groupe"

PostgreSQL n'a qu'un seul concept, le **rôle**, qui peut se connecter
(`LOGIN`) ou non, et posséder des objets (bases, tables). Un rôle
`LOGIN` sans autre attribut ne peut agir que sur ce qu'il possède ou ce
qui lui est explicitement accordé (`GRANT`) — contrairement au rôle
`postgres` par défaut (superuser, créé à l'installation), qui a autorité
sur tout le cluster. La distinction cruciale pour une application :

- **rôle applicatif** (`secure_web_lab_app` dans ce lab) — `LOGIN`
  + propriétaire de sa propre base, rien de plus. Un compromis de ce rôle
  (injection SQL, identifiants qui fuient) limite les dégâts à cette
  seule base.
- **rôle superuser** (`postgres`) — jamais utilisé par l'application elle-
  même, réservé à l'administration humaine ponctuelle (création du rôle
  applicatif, migrations manuelles exceptionnelles).

Même principe que l'utilisateur système dédié aux workers Nginx
([`Notes/nginx/utilisateur-dedie/`](../nginx/utilisateur-dedie/README.md)) —
transposé du système d'exploitation au système de gestion de base de
données, mais l'idée (un compte de service scopé au strict nécessaire)
est identique.

## Authentification : `pg_hba.conf` et la méthode selon l'origine de la connexion

PostgreSQL choisit sa méthode d'authentification selon **d'où vient la
connexion**, configuré dans `pg_hba.conf` (Host-Based Authentication) :
une connexion locale par socket Unix peut utiliser `peer` (le rôle PG
doit correspondre exactement au nom de l'utilisateur système qui se
connecte — pratique pour l'administration, sans mot de passe à taper),
tandis qu'une connexion réseau (même vers `127.0.0.1`, en TCP) utilise
typiquement un mot de passe (`scram-sha-256` sur les versions récentes,
plus robuste que l'ancien `md5`). Le backend de ce lab se connecte en TCP
vers `127.0.0.1` avec le mot de passe du rôle applicatif — jamais via
`peer`, qui supposerait un utilisateur système du même nom (aucun rapport
avec l'utilisateur système qui fait tourner le processus Node ici).

## `pg_hba.conf` : la première ligne qui correspond gagne

`pg_hba.conf` est une liste de règles (`TYPE DATABASE USER ADDRESS METHOD`)
évaluées **dans l'ordre, du haut vers le bas** — PostgreSQL applique la
**première** ligne dont les quatre premiers critères (type de connexion,
base, rôle, adresse) correspondent à la tentative de connexion, puis
s'arrête : une ligne plus permissive placée *avant* une ligne plus stricte
rend cette dernière inutile, même si elle existe plus bas dans le fichier.
Conséquence concrète pour ce lab (voir
[`postgresql/README.md`](../../postgresql/README.md) pour la config
réelle) : remplacer une ligne générique (`host all all 127.0.0.1/32 ...`,
qui correspond à *toute* base et *tout* rôle) par des lignes spécifiques
(`host secure_web_lab secure_web_lab_app 127.0.0.1/32 ...`) ne sert à rien
tant que la ligne générique reste présente plus haut — elle continuerait à
« absorber » toutes les connexions avant que les règles plus précises
n'aient la moindre chance d'être évaluées. Le resserrement doit donc
**retirer** la ligne générique, pas seulement en ajouter une plus précise
à côté.

## Modèle de privilèges : `GRANT`/`REVOKE`, le pseudo-rôle `PUBLIC`, et l'exception du propriétaire

Au-delà de `pg_hba.conf` (qui décide **si une connexion réseau est
acceptée**), PostgreSQL a un second niveau de contrôle, indépendant : une
fois connecté, quelles actions un rôle a-t-il le droit de faire sur quels
objets (`GRANT`/`REVOKE`). `PUBLIC` n'est pas un rôle réel mais un
pseudo-rôle représentant *tous* les rôles du cluster — `GRANT X TO
PUBLIC` équivaut à l'accorder à tout le monde, y compris des rôles créés
plus tard. PostgreSQL accorde par défaut `CONNECT` sur chaque nouvelle
base à `PUBLIC` : sans action explicite, n'importe quel rôle `LOGIN` du
cluster peut s'y connecter (en supposant que `pg_hba.conf` l'autorise par
ailleurs) — `REVOKE CONNECT ... FROM PUBLIC` retire ce défaut.

Exception à connaître : le **propriétaire** d'un objet (ici, une base)
conserve toujours ses privilèges dessus, même après un `REVOKE ... FROM
PUBLIC` — la propriété d'un objet implique ses privilèges, indépendamment
du système `GRANT`/`REVOKE` classique. Une des rares situations en
PostgreSQL où « révoquer tout » ne revient pas à « bloquer tout le
monde » : le propriétaire reste toujours une exception implicite.

## Timeouts de session : où les poser détermine qui ils affectent

PostgreSQL permet de régler `statement_timeout` (durée max d'une requête
avant annulation) et `idle_in_transaction_session_timeout` (durée max
qu'une transaction peut rester ouverte sans activité avant d'être
terminée) à plusieurs niveaux, avec une portée différente à chaque fois :

- `ALTER SYSTEM SET ...` — valeur par défaut pour **tout le cluster**,
  toutes connexions confondues (nécessite `pg_reload_conf()` ou un
  redémarrage selon le paramètre).
- `ALTER ROLE <role> SET ...` — valeur par défaut **seulement pour les
  sessions ouvertes sous ce rôle précis** ; un autre rôle (ex. `postgres`
  pour l'administration) n'est pas affecté. C'est ce niveau qui a du sens
  pour un rôle applicatif : on veut border les requêtes d'une appli web,
  pas une migration manuelle ponctuelle qui pourrait légitimement prendre
  plus de temps.
- `SET ... ` (sans `ALTER`) — valable seulement pour la session/transaction
  courante, perdu à la déconnexion.

Point important : un réglage posé via `ALTER ROLE ... SET` ne s'applique
qu'aux **nouvelles** connexions ouvertes après le changement — une
connexion déjà établie (ex. dans un pool applicatif) garde l'ancien
comportement jusqu'à sa prochaine reconnexion.

## Journalisation des connexions : ce qui est inconditionnel, ce qui ne l'est pas

Les **échecs d'authentification** sont toujours journalisés par
PostgreSQL (niveau `FATAL`), indépendamment de toute configuration —
aucun réglage ne peut les faire disparaître des logs. En revanche, les
connexions et déconnexions **réussies** ne sont journalisées que si
`log_connections`/`log_disconnections` sont explicitement activés (`off`
par défaut) : sans ça, les logs ne montrent que les tentatives qui ont
échoué, jamais le trafic légitime — une asymétrie à connaître si on veut
un vrai journal d'audit plutôt qu'un simple journal d'incidents.
`log_line_prefix` contrôle les informations préfixées à chaque ligne de
log (`%m` horodatage, `%p` PID, `%u` rôle, `%d` base, `%h` hôte distant,
entre autres) — `%h` en particulier est ce qui permettrait à un outil
comme fail2ban d'extraire une IP à bannir depuis ces logs, absent du
préfixe par défaut Ubuntu.

## Pourquoi une vraie base plutôt que SQLite pour ce lab

SQLite (fichier unique, zéro service à administrer) aurait été plus
simple, mais aurait donné beaucoup moins à durcir et à apprendre :
PostgreSQL est un **service réseau à part entière** (écoute sur un port,
a son propre modèle de comptes/permissions, ses propres logs, sa propre
configuration d'accès) — exactement le genre de composant que ce lab
cherche à savoir sécuriser correctement, pas seulement Nginx. Cohérent
avec l'objectif du projet : apprendre à durcir une vraie infrastructure
multi-services, pas un seul composant isolé.
