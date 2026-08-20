# Stratégie de séparation : ports plutôt que domaines seuls

## Le choix

Chaque environnement écoute sur un port distinct de la même machine :

| Environnement | Port | `server_name`                  |
|----------------|------|---------------------------------|
| dev            | 8080 | `dev.secure-web-lab.local`     |
| staging        | 8081 | `staging.secure-web-lab.local` |
| prod-lab       | 80   | `secure-web-lab.local`         |

## Pourquoi pas uniquement des noms de domaine

En infrastructure réelle, la séparation d'environnements se fait
généralement par **domaine** (`dev.example.com`, `staging.example.com`,
`example.com`), chaque nom résolvant vers une machine ou un load-balancer
différent — le port 80/443 reste le même partout. Cette approche suppose un
contrôle DNS (ou au minimum des entrées `/etc/hosts` par environnement) et,
souvent, des hôtes physiquement ou logiquement séparés (VMs, conteneurs).

Ici, une seule instance nginx sur une seule machine sert les trois
environnements. Router uniquement par `server_name` sur un unique port 80
fonctionnerait techniquement (nginx sait très bien faire cohabiter
plusieurs `server_name` sur un même port), mais demanderait de résoudre
`dev.secure-web-lab.local` et `staging.secure-web-lab.local` vers
`127.0.0.1` — via `/etc/hosts` ou un DNS local — avant de pouvoir les
tester. Utiliser des **ports distincts** permet de joindre chaque
environnement directement via `curl http://localhost:8080` sans dépendre
d'une résolution de nom supplémentaire, tout en gardant des `server_name`
différenciés pour documenter l'intention (et pour préparer une migration
future vers une vraie séparation par domaine, quand le projet évoluera vers
plusieurs hôtes ou conteneurs — voir `infra/docker/` dans l'architecture du
`ToDo.md`).

Résumé : `server_name` reste le mécanisme d'identification "propre" (celui
qui deviendrait un vrai sous-domaine en production), le port est une
béquille spécifique au lab pour fonctionner sur une seule machine sans
dépendance DNS.

## Résolution du point de vigilance `default_server`

[`Notes/nginx/configuration/repo-vs-etc-nginx.md`](../configuration/repo-vs-etc-nginx.md)
avait relevé que le comportement "default implicite" (premier server block
déclaré sur un couple adresse/port devient serveur par défaut) deviendrait
fragile dès l'ajout d'un second vhost.

Avec trois environnements, chacun écoute sur un port différent (8080, 8081,
80) : il n'y a donc toujours qu'un seul server block par port, et le risque
d'ambiguïté entre plusieurs vhosts sur un **même** port ne se présente pas
encore ici. La directive `default_server` a néanmoins été ajoutée
explicitement sur les trois configs (`listen 80 default_server;`, etc.),
par anticipation : si un jour plusieurs `server_name` doivent cohabiter sur
un même port (ex. migration vers une séparation par domaine sur le port
80/443 uniquement), le comportement par défaut sera déjà déclaré
explicitement plutôt que déduit implicitement de l'ordre des fichiers
chargés.
