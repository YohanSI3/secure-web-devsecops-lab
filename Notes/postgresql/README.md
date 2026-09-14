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

## Pourquoi une vraie base plutôt que SQLite pour ce lab

SQLite (fichier unique, zéro service à administrer) aurait été plus
simple, mais aurait donné beaucoup moins à durcir et à apprendre :
PostgreSQL est un **service réseau à part entière** (écoute sur un port,
a son propre modèle de comptes/permissions, ses propres logs, sa propre
configuration d'accès) — exactement le genre de composant que ce lab
cherche à savoir sécuriser correctement, pas seulement Nginx. Cohérent
avec l'objectif du projet : apprendre à durcir une vraie infrastructure
multi-services, pas un seul composant isolé.
