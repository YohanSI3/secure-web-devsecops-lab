# Timeouts adaptés

## Contexte

Phase 2 du `ToDo.md` : « timeouts adaptés ». Objectif : limiter le temps
qu'une connexion peut immobiliser un worker Nginx sans progresser, plutôt
que de garder les délais par défaut (60-75s), pensés pour une tolérance
maximale plutôt que pour limiter l'exposition à un client anormalement
lent.

Les valeurs retenues pour ce lab sont documentées dans
[`nginx/README.md`](../../../nginx/README.md#timeouts-adaptés) — cette
note couvre le fonctionnement général et une limite importante à
connaître.

## Ce que chaque timeout mesure réellement

Point commun aux trois timeouts d'E/S (`client_header_timeout`,
`client_body_timeout`, `send_timeout`) : ce ne sont **pas** des durées
totales pour toute la requête/réponse, mais des délais **entre deux
opérations de lecture/écriture successives**. Tant que des données
continuent d'arriver (ou d'être écrites, pour `send_timeout`) à un rythme
qui respecte le délai, la connexion reste ouverte indéfiniment, même si le
total cumulé dépasse largement la valeur configurée.

`keepalive_timeout` est différent : il mesure l'inactivité **entre deux
requêtes** sur une même connexion réutilisée, pas à l'intérieur d'une
requête en cours.

## La limite réelle face à une attaque lente délibérée (Slowloris)

Parce que ces timeouts se **réinitialisent à chaque opération réussie**,
une attaque du type *Slowloris* — un client qui envoie volontairement ses
données très lentement pour immobiliser un maximum de connexions le plus
longtemps possible — peut en théorie contourner un timeout court en
envoyant, par exemple, un seul octet toutes les 9 secondes plutôt que rien
du tout : chaque octet reçu relance le compteur, la connexion ne dépasse
jamais le délai configuré, et reste pourtant ouverte indéfiniment. Un
timeout resserré (`10s` ici plutôt que `60s`) réduit la fenêtre
d'exploitation face à un attaquant naïf (une seule grosse pause), mais ne
neutralise pas un attaquant qui calibre précisément son débit sous le
seuil.

Protection complémentaire, non implémentée dans ce lab (hors périmètre de
cette tâche) : `limit_conn`, qui borne le **nombre de connexions
simultanées** qu'une même IP peut maintenir ouvertes. Même si chaque
connexion individuelle échappe au timeout par un débit calibré, `limit_conn`
borne le nombre total de connexions qu'un même attaquant peut ainsi
immobiliser à la fois — la vraie protection structurelle contre Slowloris
combine généralement les deux : un timeout resserré (limite la durée par
connexion pour un attaquant qui ne calibre pas finement) et une limite de
connexions par IP (limite les dégâts d'un attaquant qui calibre finement).

## Pourquoi resserrer plutôt que garder les défauts

Les valeurs par défaut de Nginx (60-75s) sont pensées pour tolérer des
clients légitimes dans le pire des cas plausible (connexion mobile très
dégradée, gros formulaire sur réseau lent) — un choix orienté
compatibilité maximale plutôt que protection. Sur un site qui ne reçoit
que des requêtes courtes (pages statiques, en-têtes standards), le temps
réellement nécessaire à un client légitime pour transmettre une requête
complète se compte en millisecondes ; resserrer les timeouts à `10s`
laisse une marge très large pour l'usage réel tout en réduisant
drastiquement le temps qu'une connexion anormale peut immobiliser un
worker.
