# Protection contre divulgation de version

## Contexte

Suite du Phase 1 (`server_tokens off;`, voir
[`Notes/nginx/installation/README.md`](../installation/README.md)) et
Phase 2 du `ToDo.md`. Le fingerprinting d'un serveur web — deviner
précisément quel logiciel (et quelle version) répond — est souvent la
toute première étape d'une reconnaissance avant exploitation : une version
précise permet de croiser directement avec des CVE connues plutôt que de
tester des exploits à l'aveugle.

Les choix concrets pour ce lab sont documentés dans
[`nginx/README.md`](../../../nginx/README.md#protection-contre-divulgation-de-version) —
cette note couvre la distinction entre les différents niveaux de fuite
d'information possibles et ce que Nginx permet ou non de corriger nativement.

## Trois niveaux de fuite, pas un seul

- **Version précise** (`nginx/1.24.0`) — le niveau le plus dangereux :
  permet de cibler directement des vulnérabilités connues pour cette
  version exacte. C'est ce que `server_tokens off;` supprime, dans le
  header `Server:` et dans le pied de page des pages d'erreur par défaut.
- **Identité du logiciel** (`nginx`, sans version) — moins critique (pas
  de CVE précise à cibler directement), mais oriente déjà l'attaquant :
  il sait quelles techniques/outils spécifiques à Nginx tester plutôt que
  de considérer toutes les possibilités (Apache, Caddy, IIS...).
  `server_tokens off;` ne supprime **pas** ce niveau : le header reste
  `Server: nginx`, et le pied de page des pages d'erreur par défaut
  continue d'afficher `nginx`.
- **Empreinte comportementale** (fingerprinting passif) — même sans aucun
  header explicite, la manière dont un serveur répond (ordre des headers,
  formatage précis des erreurs, comportement TLS/HTTP2) peut suffire à un
  outil spécialisé (type `wafw00f`, `httprint`) à deviner le logiciel avec
  une bonne confiance. Aucune configuration simple ne neutralise
  totalement ce niveau — hors périmètre de cette tâche.

## Pourquoi le header `Server:` ne peut pas être supprimé simplement

Le header `Server:` est généré par le **cœur** de Nginx
(`ngx_http_header_filter_module`), pas par un module optionnel qu'on
pourrait désactiver. `server_tokens` contrôle uniquement s'il inclut la
version ou non (`nginx` vs `nginx/1.24.0`) — il n'existe pas de directive
native pour le supprimer entièrement ou le remplacer par une autre valeur.
Deux voies existent en dehors d'une configuration standard :

- **Module tiers non officiel** (`ngx_headers_more`, très utilisé mais pas
  maintenu par le projet Nginx lui-même) offrant `more_clear_headers` /
  `more_set_headers` pour retirer ou réécrire n'importe quel header,
  y compris `Server:`. Nécessite de compiler Nginx avec ce module (les
  paquets Ubuntu standards ne l'incluent pas), ce qui casserait la
  reproductibilité par version pinnée déjà en place
  ([`scripts/install-nginx.sh`](../../../scripts/install-nginx.sh)).
- **Recompilation depuis les sources** en modifiant directement la chaîne
  de version dans le code (`src/core/nginx.h`) — techniquement possible,
  mais un changement bien plus lourd qu'un ajustement de configuration,
  et qui sortirait du modèle "paquet Ubuntu officiel" déjà choisi et
  documenté pour ce lab.

Ni l'une ni l'autre retenue ici : le compromis choisi accepte que
`Server: nginx` reste visible, et concentre l'effort sur ce qui est
atteignable en configuration standard — les pages d'erreur personnalisées,
qui elles suppriment complètement toute mention du logiciel dans le corps
des réponses d'erreur.

## Pourquoi une page d'erreur générique plutôt qu'une par code

Une page par code (`404.html`, `429.html`, ...) permettrait un message
plus précis pour chaque situation, au prix d'un fichier de plus à
maintenir par code, et d'un risque de divergence si un seul est mis à
jour et pas les autres. Une page unique
([`app/static-site/error.html`](../../../app/static-site/error.html))
réutilisée pour tous les codes gérés reste cohérente avec l'objectif
principal ici (ne rien révéler du logiciel serveur), quitte à perdre en
finesse de message — un compromis délibéré pour ce lab, pas une
contrainte technique de Nginx (`error_page` accepte très bien une cible
différente par code).
