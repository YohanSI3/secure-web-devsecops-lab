# Chaque header expliqué

Référence : [`nginx/snippets/security-headers.conf`](../../../nginx/snippets/security-headers.conf)

## `server_tokens off;`

Ne concerne pas un header ajouté mais un header **retiré/simplifié** : par
défaut, nginx annonce sa version exacte dans le header `Server:` (ex.
`nginx/1.24.0 (Ubuntu)`) et sur ses pages d'erreur par défaut.
`server_tokens off;` réduit ça à `nginx` seul. Objectif : ne pas faciliter
la tâche d'un attaquant qui chercherait une vulnérabilité connue liée à une
version précise (voir `Notes/nginx/installation/` — traçabilité de
version, même logique côté défense : ce qu'on sait exposer volontairement
ne doit pas inclure ce qui n'apporte rien au client légitime). Ce n'est pas
une protection en soi (la version reste déductible par d'autres moyens),
mais une réduction de surface d'information gratuite.

## `Strict-Transport-Security` (HSTS)

```
Strict-Transport-Security: max-age=31536000; includeSubDomains
```

Indique au navigateur : "pendant `max-age` secondes (ici 1 an), ne jamais
retenter une connexion HTTP à ce domaine — utilise HTTPS directement,
même si l'utilisateur tape `http://` ou clique un lien en `http://`."
Protège contre les attaques de type "SSL stripping" (un attaquant
intercepte la première requête HTTP avant la redirection vers HTTPS pour
rester en clair). `includeSubDomains` étend la règle à tous les
sous-domaines. Volontairement **sans `preload`** ici : le preload inscrit
un domaine dans une liste embarquée dans les navigateurs, quasiment
irréversible en production réelle — inutile et hors sujet pour un domaine
`.local` de lab, mais bonne habitude à ne pas ajouter par réflexe.

N'a d'effet que sur une réponse déjà servie en HTTPS (un navigateur ignore
ce header reçu en HTTP) — raison pour laquelle il est inclus uniquement
dans les server blocks HTTPS, pas dans les blocs de redirection HTTP.

## `X-Content-Type-Options: nosniff`

Empêche le navigateur de deviner ("sniffer") lui-même le type d'un fichier
à partir de son contenu plutôt que de faire confiance au header
`Content-Type` envoyé par le serveur. Sans ce header, un fichier uploadé
par un attaquant avec une extension anodine mais un contenu HTML/JS
pourrait, dans certains scénarios, être interprété et exécuté comme tel par
le navigateur au lieu d'être traité selon son `Content-Type` déclaré.

## `X-Frame-Options: DENY`

Empêche la page d'être chargée dans une `<iframe>` sur un autre site.
Protège contre le "clickjacking" (superposer une iframe invisible du site
ciblé au-dessus d'une interface trompeuse pour piéger un clic de
l'utilisateur). Header historique, aujourd'hui recouvert par la directive
`frame-ancestors` de la CSP (voir plus bas) — conservé quand même pour la
compatibilité avec d'anciens navigateurs qui ne lisent pas cette directive
CSP.

## `Referrer-Policy: strict-origin-when-cross-origin`

Contrôle l'information transmise dans le header `Referer` quand
l'utilisateur navigue depuis cette page vers une autre. Cette politique
envoie l'URL complète pour une navigation vers le même site, mais réduit
l'information à l'origine seule (schéma + domaine, sans chemin ni
paramètres) pour une navigation vers un site externe, et rien du tout si on
passe de HTTPS vers HTTP. Évite qu'une URL contenant des informations
sensibles dans son chemin ou ses paramètres (ex. un token dans une query
string) ne fuite vers un site tiers via ce header. C'est le comportement
par défaut de la plupart des navigateurs modernes — le déclarer
explicitement documente l'intention plutôt que de dépendre d'un défaut
implicite du client.

## `Content-Security-Policy` (CSP)

```
Content-Security-Policy: default-src 'self'; base-uri 'self'; frame-ancestors 'none'
```

Déclare explicitement quelles origines la page a le droit de charger pour
chaque type de ressource (scripts, styles, images, polices, requêtes
réseau...). `default-src 'self'` restreint tout, par défaut, à l'origine du
site lui-même — aucune ressource externe autorisée. C'est la défense
principale contre les attaques XSS (Cross-Site Scripting) : même si un
attaquant parvient à injecter du contenu malveillant dans la page, une CSP
stricte bloque l'exécution de script ou le chargement de ressource depuis
une origine non autorisée.

- `base-uri 'self'` empêche un contenu injecté de modifier la balise
  `<base>` de la page (qui changerait sinon la résolution de toutes les
  URLs relatives).
- `frame-ancestors 'none'` est la version moderne, standardisée dans la
  CSP, de `X-Frame-Options: DENY` — empêche explicitement toute page
  externe d'embarquer celle-ci en iframe.

**Conséquence directe sur le code** : une CSP avec `default-src 'self'`
bloque par défaut le CSS inline (`<style>` dans le HTML) sauf à affaiblir
la politique avec `'unsafe-inline'`. Plutôt que d'affaiblir la CSP, le CSS
de `app/static-site/index.html` a été déplacé dans un fichier
`style.css` séparé, chargé via `<link rel="stylesheet">` — une ressource
`'self'` classique, pleinement compatible avec une CSP stricte. La
contrainte de sécurité a directement dicté une meilleure pratique de code
(séparation contenu/présentation), pas l'inverse.

## `Permissions-Policy`

```
Permissions-Policy: geolocation=(), microphone=(), camera=()
```

Désactive explicitement l'accès à certaines API navigateur sensibles
(géolocalisation, micro, caméra) pour cette page, même si un script tiers
malveillant parvenait à s'exécuter malgré la CSP. Aucune de ces API n'est
utilisée par le site actuel — les désactiver explicitement ferme des
capacités qui n'ont aucune raison d'être disponibles, plutôt que de laisser
le navigateur les autoriser par défaut sans que rien n'en ait jamais
besoin.

## Header volontairement absent : `X-XSS-Protection`

Souvent présent dans les listes "classiques" de headers de sécurité
(`X-XSS-Protection: 1; mode=block`), ce header contrôlait un filtre XSS
intégré aux anciens navigateurs. Il est aujourd'hui obsolète : les
navigateurs modernes ont retiré ce filtre (il introduisait lui-même des
vulnérabilités dans certains cas) et s'appuient sur la CSP à la place.
L'ajouter n'aurait plus d'effet réel — volontairement omis plutôt que
copié par réflexe depuis une liste générique trouvée en ligne.
