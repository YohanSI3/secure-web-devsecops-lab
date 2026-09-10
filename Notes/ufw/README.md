# Firewall Linux : netfilter, iptables, ufw

## Contexte

Phase 2 du `ToDo.md` : « firewall ». Après avoir réduit les privilèges des
processus Nginx eux-mêmes ([`Notes/nginx/utilisateur-dedie/`](../nginx/utilisateur-dedie/README.md)),
étape suivante de la défense en profondeur : contrôler, au niveau du
système, quels ports peuvent même recevoir une connexion — indépendamment
de ce que Nginx écoute ou non dans sa config.

Détail réparti dans deux fichiers :

- [`netfilter-iptables-ufw.md`](netfilter-iptables-ufw.md) — les trois
  couches (noyau, outil bas niveau, frontend simplifié), ce que chacune
  fait réellement.
- [`reseau-wsl2-et-portee-du-filtrage.md`](reseau-wsl2-et-portee-du-filtrage.md)
  — pourquoi un firewall configuré dans une VM WSL2 ne filtre pas la même
  chose qu'un firewall sur un serveur physique/cloud classique.

Les règles concrètes retenues pour ce lab (quels ports, pourquoi, script)
sont documentées dans
[`firewall/README.md`](../../firewall/README.md) — cette note-ci ne
couvre que le fonctionnement général, pas les choix spécifiques au projet.

## Suite

Phase 2 du `ToDo.md` terminée. Voir [`nginx/README.md`](../../nginx/README.md)
pour le détail de chaque point traité ensuite.
