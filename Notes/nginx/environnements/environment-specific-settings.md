# Ce qui diffère entre les environnements

Les trois configs (`secure-web-lab-{dev,staging,prod}.conf`) partagent la
même structure (voir
[`Notes/nginx/configuration/server-block-directives.md`](../configuration/server-block-directives.md)
pour le détail des directives communes) mais diffèrent sur quelques points
volontaires.

## Contenu identique, configuration différente

Les trois environnements servent exactement le même contenu source
(`app/static-site/`), déployé vers trois webroots distincts
(`/var/www/secure-web-lab-{dev,staging,prod}`). Seule la **configuration
nginx** varie, pas le code applicatif. C'est le principe (issu des
[Twelve-Factor Apps](https://12factor.net/fr/config)) de séparer
strictement code et configuration : le même artefact déployé doit pouvoir
se comporter différemment selon son environnement d'exécution, sans
modification du code lui-même. Concrètement, cela évite de devoir
maintenir des branches de code différentes par environnement — seule la
configuration change.

## `autoindex`

- `dev` : `autoindex on;`
- `staging` / `prod-lab` : `autoindex off;`

`autoindex` fait lister par nginx le contenu d'un répertoire (façon
listing de fichiers) quand aucun fichier `index` n'y est trouvé. Pratique
en développement pour naviguer rapidement dans les fichiers déployés sans
configurer de route dédiée. C'est en revanche une mauvaise pratique de
sécurité en dehors de cet usage : un répertoire indexé expose la structure
et les noms de fichiers présents (configs, sauvegardes oubliées, fichiers
temporaires) à quiconque devine ou tombe sur l'URL, sans contrôle d'accès.
D'où la désactivation explicite en staging et prod-lab — comportement par
défaut de nginx de toute façon, mais rendu explicite ici pour documenter
l'intention plutôt que de dépendre d'un défaut implicite.

## Header `X-Environment`

Chaque config ajoute un header de réponse HTTP personnalisé
(`add_header X-Environment "<env>" always;`), visible via
`curl -I`. Objectif : pouvoir vérifier rapidement, depuis n'importe quel
outil HTTP, quel environnement a répondu à une requête — utile en test
manuel, mais aussi le genre de mécanisme qu'un pipeline CI pourrait
vérifier automatiquement plus tard (Phase 3) pour confirmer qu'un
déploiement a atteint le bon environnement.

Le mot-clé `always` force l'ajout du header même sur les réponses d'erreur
(4xx/5xx) — sans lui, `add_header` n'ajoute le header que sur les réponses
de code 2xx/3xx par défaut, ce qui aurait rendu le diagnostic incomplet en
cas d'erreur.

Note de sécurité pour plus tard (Phase 2, "headers de sécurité de base") :
un header custom comme celui-ci révèle volontairement de l'information sur
l'infrastructure. Acceptable ici dans un lab pour faciliter
l'apprentissage et le diagnostic, mais un tel header ne devrait pas exister
sur un vrai environnement de production exposé publiquement — principe
plus large de ne pas divulguer d'informations internes inutiles
(rejoint le point `server_tokens off;` déjà identifié dans le `ToDo.md`).

## Logs séparés par environnement

Chaque config garde des fichiers `access_log`/`error_log` dédiés
(`secure-web-lab-<env>.access.log`/`.error.log`), déjà justifié dans
[`Notes/nginx/configuration/server-block-directives.md`](../configuration/server-block-directives.md).
Avec trois environnements actifs simultanément sur la même machine, cette
séparation devient nécessaire (et pas seulement pratique) : sans elle, le
trafic de dev, staging et prod-lab se retrouverait mélangé dans les mêmes
fichiers, rendant impossible de distinguer, par exemple, un pic d'erreurs
en dev (attendu, changements fréquents) d'un pic d'erreurs en prod-lab
(à investiguer sérieusement).
