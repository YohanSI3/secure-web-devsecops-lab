# Utilisateur dédié et permissions minimales

## Statut

Rédigé (scripts, config, rationale) mais **pas encore exécuté sur une
machine réelle** au moment de l'écriture de cette note — contrairement aux
autres notes du dépôt, qui documentent un geste déjà posé. Les sections
« Ce qui a été fait » et « Vérification » ci-dessous seront complétées avec
les sorties réelles une fois les scripts exécutés (voir ordre ci-dessous),
en respectant la convention de journal de ce dossier plutôt que d'inventer
des transcripts.

## Contexte

Suite de la Phase 2 du `ToDo.md` : « utilisateur dédié » et « permissions
minimales », traités ensemble car le second découle directement du premier
— changer l'identité des workers nginx implique de revoir tout ce qui leur
donne accès (webroot, répertoires temporaires).

Jusqu'ici, les workers nginx tournent sous `www-data`, l'utilisateur défini
par défaut par le paquet Debian/Ubuntu (voir
[`Notes/nginx/installation/README.md`](../installation/README.md#modèle-de-privilèges--utilisateur-système-masterworker)).
`www-data` est **partagé par convention** entre plusieurs services
potentiels d'une même machine (PHP-FPM, Apache, autres applis web). Sur une
machine qui n'héberge que ce lab, ce n'est pas un risque immédiat, mais ça
reste une mauvaise habitude par défaut : un utilisateur dédié à ce service
précis limite le rayon d'impact d'une compromission — un worker nginx
compromis n'hérite d'aucun accès pensé pour un autre service qui
utiliserait `www-data`, et réciproquement.

Détail réparti dans deux fichiers séparés :

- [`creation-et-configuration-utilisateur.md`](creation-et-configuration-utilisateur.md)
  — création de l'utilisateur/groupe système, et pourquoi la directive
  `user` de Nginx ne peut pas être gérée comme les autres réglages de ce
  dépôt (`conf.d/`, `snippets/`).
- [`permissions-et-repertoires-temporaires.md`](permissions-et-repertoires-temporaires.md)
  — revue complète de ce qui doit changer (webroot, `/var/lib/nginx/`) et de
  ce qui reste inchangé (certificats TLS, logs) suite au changement
  d'utilisateur, avec la justification pour chacun.

## Portée : un seul utilisateur pour les trois environnements

Les trois vhosts (dev/staging/prod-lab) sont servis par la **même** instance
Nginx (un seul master, un même jeu de workers, cf.
[`Notes/nginx/environnements/`](../environnements/README.md)) — la directive
`user` est globale à l'instance, pas par `server{}`. Un utilisateur dédié
*par environnement* n'apporterait donc aucune isolation réelle : les
workers d'un même processus peuvent de toute façon lire les trois webroots
simultanément, quel que soit le nombre d'utilisateurs système déclarés. Une
vraie séparation par environnement demanderait des instances Nginx
distinctes (hors périmètre actuel, cf. limite déjà notée dans
[`Notes/nginx/installation/README.md`](../installation/README.md) sur une
migration éventuelle vers Docker).

## Marche à suivre (ordre important)

```bash
./scripts/create-nginx-user.sh      # crée l'utilisateur/groupe système
./scripts/configure-nginx-user.sh   # bascule Nginx dessus, ajuste /var/lib/nginx, reload
./scripts/deploy-all-environments.sh # redéploie le webroot avec le nouveau groupe propriétaire
```

Cet ordre évite un creux d'accès : les workers basculent sur le nouvel
utilisateur (étape 2) avant que le webroot ne soit re-chown vers le nouveau
groupe (étape 3) — inverser les deux laisserait une fenêtre où les workers
(encore `www-data`) ne pourraient plus lire un webroot déjà passé au
nouveau groupe.

## Vérification

```bash
ps -eo user,pid,cmd | grep '[n]ginx: worker process'
# attendu : secure-web-lab, plus www-data

curl -skI --resolve secure-web-lab.local:443:127.0.0.1 https://secure-web-lab.local/
# attendu : 200 OK, inchangé côté client — le changement est invisible
# fonctionnellement, uniquement une réduction de privilèges côté serveur
```

*(sorties réelles à ajouter ici après exécution)*

## Prochaines étapes (Phase 2)

- firewall
- fail2ban ou équivalent
- rate limiting
- contrôle des tailles de requêtes
- timeouts adaptés
