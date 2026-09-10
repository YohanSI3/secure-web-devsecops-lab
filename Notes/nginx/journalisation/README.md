# Journalisation avancée

## Contexte

Phase 2 du `ToDo.md` : « journalisation avancée ». Contrairement à la
rotation de logs (prochain point du plan, mécanique de gestion des
fichiers), cette étape porte sur le **contenu** de chaque ligne de log :
quelles informations y figurent, et pourquoi le format `combined` par
défaut ne suffit plus une fois plusieurs mécanismes de rejet actifs
(rate limiting, contrôle de taille, méthodes non supportées).

Les choix concrets sont documentés dans
[`nginx/README.md`](../../../nginx/README.md#journalisation-avancée) —
cette note couvre le fonctionnement général des éléments ajoutés.

## Niveaux de sévérité : un piège d'ordre, pas de syntaxe

Nginx classe ses messages d'erreur par **niveau de sévérité** (du plus
verbeux au plus grave : `debug`, `info`, `notice`, `warn`, `error`,
`crit`, `alert`, `emerg`). La directive `error_log <fichier> <niveau>;`
fixe un **seuil** : seuls les messages de ce niveau et des niveaux plus
graves sont écrits dans le fichier — pas une sélection d'un niveau
précis, un plancher.

Piège rencontré ici : une directive comme `limit_req_log_level warn;`
choisit à quel niveau un module (`limit_req`) **génère** son message, mais
n'a aucun effet si le `error_log` du vhost concerné garde son seuil par
défaut (`error`, plus grave que `warn`) — le message est bien produit par
le module, puis immédiatement écarté par le filtre de seuil du fichier de
sortie, sans erreur ni avertissement visible : le fichier reste
simplement vide pour ce type d'événement. Les deux réglages (niveau de
génération **et** seuil du fichier de destination) doivent être cohérents
entre eux ; changer l'un sans l'autre ne produit aucune erreur de
configuration détectable par `nginx -t`, seulement une absence silencieuse
de données au moment où on s'attend à les voir.

## Pourquoi enrichir le format plutôt que garder `combined`

Le format `combined` (implicite quand `access_log` ne précise pas de nom
de format) date d'une époque où Nginx ne faisait que servir des fichiers
statiques sans notion de rejet de trafic. Une fois du rate limiting, des
limites de taille et des restrictions de méthode en place, la seule
information « code de statut » ne dit pas *pourquoi* — un `429` et un
`200` sont déjà distinguables par le statut, mais rien ne dit combien de
temps la requête a mis (`$request_time`), ni sur quelle version de TLS
elle est arrivée (`$ssl_protocol`/`$ssl_cipher`), ni comment retrouver
cette ligne précise depuis la réponse reçue par le client.

## `$request_id` : corrélation client ↔ log

`$request_id` est une variable core de Nginx (aucun module requis) :
une chaîne hexadécimale générée aléatoirement, unique par requête.
Répétée à la fois dans le log (`req_id=...`) et dans un header de réponse
(`X-Request-Id`), elle permet de retrouver la ligne de log exacte
correspondant à une réponse précise qu'un client aurait reçue — utile en
support (« voici l'identifiant de ma requête qui a échoué ») comme en
debug local, sans dépendre d'une corrélation approximative par timestamp
(imprécise dès que plusieurs requêtes arrivent à la même seconde).

## Limite assumée : pas encore de format structuré (JSON)

Le format choisi ici reste du texte positionnel (comme `combined`), pas du
JSON. Un format structuré faciliterait un traitement automatisé futur
(Phase 5 du `ToDo.md` : dashboards, logs centralisés) sans dépendre d'une
expression régulière fragile pour re-découper chaque champ. Non fait ici
volontairement : cette tâche vise une journalisation plus informative
pour un usage humain immédiat (lecture directe du fichier), pas encore la
préparation d'un pipeline d'ingestion — sujet à traiter au moment de la
Phase 5, quand l'outil de centralisation réel sera choisi (ses
contraintes de format guideront mieux ce choix qu'une anticipation
aujourd'hui).
