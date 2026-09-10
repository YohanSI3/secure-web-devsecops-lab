# fail2ban : bannissement automatique basé sur les logs

## Contexte

Phase 2 du `ToDo.md` : « fail2ban ou équivalent ». Complète le
[firewall](../ufw/README.md) : ufw décide *à l'avance* quels ports peuvent
recevoir du trafic ; fail2ban décide, *a posteriori*, qu'une IP précise
qui a déjà eu le droit de se connecter s'est comportée de façon abusive, et
lui retire ce droit dynamiquement.

Détail dans [`jails-filtres-actions.md`](jails-filtres-actions.md) — les
choix concrets pour ce lab (quelles jails, quels seuils) sont documentés
dans [`fail2ban/README.md`](../../fail2ban/README.md).

## IDS ou IPS ?

Terminologie à préciser : une **IDS** (*Intrusion Detection System*, ex.
Snort, Suricata en mode détection) se contente de repérer une activité
suspecte et d'alerter — elle n'agit pas sur le trafic elle-même. fail2ban
va plus loin : il **agit** automatiquement (bannir l'IP), ce qui en fait
plutôt une **IPS** (*Intrusion Prevention System*) légère, basée sur
l'analyse de logs plutôt que sur l'inspection en ligne du trafic réseau
(par opposition à une IPS réseau classique, qui intercepte les paquets en
direct). La distinction n'est pas qu'un détail de vocabulaire : elle
implique une limite de fond (voir plus bas, « Ce que fail2ban ne voit
pas ») — fail2ban ne réagit qu'*après* que la requête a déjà atteint
Nginx et a été journalisée, jamais avant.

## Ce que fail2ban ne voit pas

fail2ban lit des fichiers de logs déjà écrits — il n'intercepte rien en
temps réel au niveau réseau. Conséquences :

- la ou les requêtes qui déclenchent le seuil de bannissement (ex. la
  10ᵉ requête 404 dans la fenêtre de temps définie) ont déjà été traitées
  par Nginx avant que fail2ban ne réagisse et bannisse l'IP pour la
  **suite** — pas de protection sur les toutes premières requêtes d'une
  attaque, seulement sur sa continuation ;
- dépend entièrement de ce qui est journalisé et de la rapidité avec
  laquelle le fichier de log est mis à jour (`backend = auto` de fail2ban
  choisit entre `pyinotify`, `gamin`, ou du polling selon ce qui est
  disponible sur la machine — voir
  [`jails-filtres-actions.md`](jails-filtres-actions.md)) ;
- un bannissement est temporaire (`bantime`) : passé ce délai, l'IP est de
  nouveau autorisée à se connecter et peut recommencer.

## Suite

Phase 2 du `ToDo.md` terminée. Voir [`nginx/README.md`](../../nginx/README.md)
pour le détail de chaque point traité ensuite (TLS, rate limiting,
contrôle des tailles de requêtes, timeouts, divulgation de version,
journalisation, rotation de logs).
