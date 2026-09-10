# Netfilter, iptables, ufw : trois couches, pas trois outils concurrents

## Le noyau : netfilter

**netfilter** est le sous-système du noyau Linux qui intercepte les
paquets réseau à différents points de leur trajet (avant routage, vers un
processus local, avant de quitter la machine, etc.) et permet de leur
appliquer des décisions : laisser passer, rejeter, modifier, journaliser.
C'est la brique qui fait le travail réel de filtrage — tout ce qui suit
n'est qu'une façon de lui dicter des règles. Sans netfilter (ou son
successeur `nftables`, qui vise à terme à le remplacer avec une syntaxe
unifiée), aucun outil en espace utilisateur ne pourrait filtrer quoi que
ce soit : le filtrage doit se faire dans le noyau, avant que les données
n'atteignent une application, pour être fiable.

## L'outil bas niveau : iptables

**iptables** est l'outil historique en ligne de commande pour écrire des
règles dans netfilter. Vocabulaire central :

- **table** — regroupe des règles par finalité (`filter` pour
  accepter/rejeter, `nat` pour traduire des adresses, etc.). `filter` est
  la seule pertinente pour un firewall simple.
- **chaîne** — une table contient des chaînes, parcourues à des moments
  précis du trajet d'un paquet : `INPUT` (paquet à destination de cette
  machine), `OUTPUT` (paquet émis par cette machine), `FORWARD` (paquet
  qui ne fait que traverser la machine, pertinent pour un routeur — sans
  objet ici, ce lab ne route rien pour d'autres machines).
- **règle** — un critère de correspondance (port, protocole, adresse
  source...) associé à une action (`ACCEPT`, `DROP`, `REJECT`...).

`iptables` est puissant mais verbeux et facile à mal utiliser : l'ordre des
règles compte (la première correspondance gagne), et une erreur de syntaxe
ou d'ordre peut se solder par un firewall qui bloque tout, y compris
l'accès qu'on utilisait pour le configurer.

## Le frontend simplifié : ufw (Uncomplicated Firewall)

**ufw** ne remplace pas iptables/netfilter : c'est une surcouche qui
génère des règles iptables (ou nftables selon la version) à partir d'une
syntaxe très simplifiée, pensée pour les cas courants d'un poste ou petit
serveur (pas d'infrastructure de routage complexe).

```bash
ufw default deny incoming     # politique par défaut : tout refuser en entrée
ufw default allow outgoing    # ... mais tout autoriser en sortie
ufw allow 443/tcp             # exception explicite
ufw enable                    # active le filtrage
```

Une seule commande `ufw allow 443/tcp` génère en réalité plusieurs règles
iptables (gestion du protocole, de l'état de connexion, etc.) — la valeur
d'ufw est précisément de ne pas avoir à les écrire à la main pour les cas
standards.

## Pourquoi une politique par défaut *deny* plutôt que *allow*

Deux philosophies possibles pour n'importe quel contrôle d'accès :

- **liste noire (default allow)** — tout est permis sauf ce qu'on bloque
  explicitement. Facile à démarrer, mais oublie fatalement des cas : toute
  nouvelle porte ouverte par erreur (un service qui démarre et écoute sur
  un port, une mauvaise config) est exposée par défaut tant que personne
  n'a pensé à la bloquer.
- **liste blanche (default deny)** — tout est refusé sauf ce qu'on
  autorise explicitement. Plus contraignant à mettre en place (il faut
  identifier tout ce qui doit réellement passer), mais un nouveau service
  qui se met à écouter sur un port ne devient pas automatiquement accessible
  depuis le réseau — il faut un geste explicite pour l'exposer.

Le default-deny est le choix cohérent avec le principe de moindre
privilège déjà appliqué ailleurs dans ce lab (utilisateur dédié aux
workers Nginx, permissions webroot minimales) : la sécurité par défaut ne
doit pas dépendre de la mémoire de quelqu'un pour bloquer *a posteriori*
ce qui ne devrait pas être exposé.

## Filtrage à état (stateful)

netfilter garde en mémoire l'état des connexions en cours (table de suivi
de connexion / *connection tracking*). Une règle `allow outgoing`
n'autorise pas seulement l'émission d'un paquet : elle autorise
implicitement les paquets de **retour** de cette même connexion, sans
avoir besoin d'une règle `allow incoming` séparée pour ce trafic-là. C'est
ce qui permet une politique `deny incoming` stricte sans casser les
connexions initiées *depuis* la machine (résolution DNS, `apt update`,
etc.) : le paquet de réponse à une requête sortante n'est pas considéré
comme une connexion entrante nouvelle.
