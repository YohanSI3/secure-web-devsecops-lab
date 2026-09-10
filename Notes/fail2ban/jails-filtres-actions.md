# Architecture de fail2ban : jail, filtre, action

fail2ban assemble trois éléments distincts pour chaque règle de
surveillance, appelée **jail** :

```text
logs → [ FILTRE : quelle ligne compte comme un échec ? ]
     → [ JAIL : combien d'échecs, dans quelle fenêtre, avant de bannir ? ]
     → [ ACTION : comment bannir concrètement ? ]
```

## Filtre (`filter.d/*.conf`)

Une expression régulière qui définit ce qu'est une tentative "ratée" dans
une ligne de log. Le jeton spécial `<HOST>` capture une adresse IP (v4 ou
v6) à l'endroit attendu dans la ligne — fail2ban le remplace en interne par
un pattern d'adresse IP tout fait, pas besoin de l'écrire à la main.

Des filtres prêts à l'emploi sont livrés avec le paquet (`nginx-http-auth`,
`nginx-botsearch`, `sshd`, `apache-auth`, etc.), pensés pour des cas
génériques. Rien n'empêche d'en écrire un propre quand le cas est
spécifique à un projet donné (ex. `nginx-404-flood`, écrit pour ce lab —
voir [`fail2ban/README.md`](../../fail2ban/README.md) pour pourquoi ce cas
précis ne correspond à aucun filtre livré par défaut).

## Jail (`jail.conf` / `jail.local`)

Une jail relie un filtre à un ou plusieurs fichiers de logs (`logpath`) et
fixe les seuils :

- **`findtime`** — la fenêtre de temps glissante dans laquelle on compte
  les échecs.
- **`maxretry`** — le nombre d'échecs, dans cette fenêtre, qui déclenche le
  bannissement.
- **`bantime`** — la durée du bannissement une fois déclenché.

`jail.conf` (fourni par le paquet, ne pas modifier) définit les valeurs par
défaut et la liste des jails disponibles mais désactivées. `jail.local`
(à créer soi-même, jamais écrasé par une mise à jour du paquet) surcharge
ce qui est nécessaire — convention identique dans l'esprit à
`sites-available`/`sites-enabled` de Nginx : séparer ce que le paquet
fournit de ce qu'on active/personnalise réellement.

## Action (`action.d/*.conf`)

Ce qui se passe concrètement quand le seuil est atteint : la plupart du
temps, ajouter une règle de pare-feu qui bloque l'IP (`iptables-multiport`,
`ufw`, `nftables`...), mais une action peut aussi être un simple envoi
d'e-mail ou un webhook — fail2ban ne bannit pas forcément via un pare-feu,
bannir est juste l'action la plus commune. Le choix retenu pour ce lab est
détaillé dans
[`fail2ban/README.md`](../../fail2ban/README.md#action-de-bannissement-iptables-multiport-défaut-pas-ufw).

## Comment fail2ban détecte qu'un fichier de log a changé (`backend`)

`backend = auto` (valeur par défaut) choisit, dans l'ordre de préférence,
un mécanisme de notification du système de fichiers (`pyinotify` sous
Linux — le noyau prévient fail2ban dès qu'une ligne est ajoutée, sans
qu'il ait besoin de revérifier lui-même) et retombe sur du **polling**
(relire le fichier à intervalle régulier) si aucun mécanisme de
notification n'est disponible. Le polling introduit un délai de détection
correspondant à l'intervalle de vérification ; `pyinotify` réagit quasiment
en temps réel dès l'écriture de la ligne. Sous WSL2, `pyinotify` fonctionne
normalement (le système de fichiers ext4 de la VM Linux le supporte
pleinement) — le point de vigilance concernerait plutôt un fichier de log
situé sur un montage `/mnt/c` (système de fichiers Windows via `drvfs`), où
le support des notifications d'écriture est plus limité. Sans objet ici :
les logs Nginx de ce lab vivent sous `/var/log/nginx/`, dans le système de
fichiers natif de la VM.
