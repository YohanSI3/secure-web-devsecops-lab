# Sessions côté serveur vs JWT : où vit l'état ?

Une fois un utilisateur authentifié, il faut un moyen de ne pas lui
redemander ses identifiants à chaque requête. Deux modèles dominent.

## Sessions côté serveur

Le serveur crée un enregistrement (« session ») contenant l'état
(`userId`, `role`, etc.), stocké **côté serveur** (mémoire, Redis, ou une
base comme dans ce lab). Le client ne reçoit qu'un identifiant opaque
(cookie), qui ne veut rien dire par lui-même — juste une clé vers
l'enregistrement serveur.

- **Révocation immédiate** : supprimer l'enregistrement déconnecte
  l'utilisateur instantanément, y compris pour des requêtes déjà "en
  vol" avec l'ancien cookie.
- **État consultable/modifiable côté serveur** à tout moment (changer un
  rôle en base de session sans repasser par le client).
- **Coût** : une consultation du stockage de session à chaque requête (un
  aller-retour DB dans ce lab) — accepté ici car son coût est marginal
  comparé à une vraie base de données déjà interrogée par ailleurs.

## JWT (JSON Web Token)

Le serveur signe cryptographiquement un jeton contenant directement les
informations (`userId`, `role`, date d'expiration) — le jeton **se
suffit à lui-même** : n'importe quel serveur qui connaît la clé de
signature peut le vérifier sans consulter de base de données.

- **Sans état côté serveur** : pas de stockage à interroger, scalabilité
  simple sur plusieurs serveurs sans stockage partagé.
- **Révocation difficile** : un JWT signé reste valide jusqu'à son
  expiration, même si on veut "déconnecter" l'utilisateur avant —
  nécessite une liste de révocation (qui réintroduit un état côté
  serveur, annulant une partie de l'intérêt du JWT) ou des expirations
  très courtes combinées à un jeton de rafraîchissement.
- Bien adapté à une API consommée par plusieurs services indépendants qui
  ne partagent pas de stockage de session commun.

## Choix pour ce lab : sessions

Un cas d'usage IAM typique (désactiver un compte compromis, forcer une
déconnexion) veut un effet **immédiat** — argument déterminant en faveur
des sessions ici, où PostgreSQL sert déjà de stockage central (voir
[`Notes/postgresql/README.md`](../postgresql/README.md)). Le JWT reste
pertinent à connaître : utile le jour où ce backend devrait exposer une
API consommée par un tiers qui ne peut pas partager l'accès à la base de
sessions.
