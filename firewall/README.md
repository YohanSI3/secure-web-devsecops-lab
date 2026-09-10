# Firewall (ufw)

Documentation technique du firewall de ce lab — ce qui est réellement
configuré et pourquoi. Pour comprendre le fonctionnement général d'un
firewall Linux (netfilter, iptables, ufw, politique par défaut), voir
[`Notes/ufw/`](../Notes/ufw/README.md).

## Politique

```text
default deny incoming
default allow outgoing
```

Aucun trafic entrant n'est autorisé sauf exception explicite. Le trafic
sortant reste ouvert : ce lab n'a pas besoin de restreindre ce que la
machine elle-même initie vers l'extérieur (mises à jour apt, résolution
DNS, etc.), seulement ce qui peut lui être adressé depuis le réseau.

## Ports ouverts

| Port | Protocole | Usage | Référence |
|---|---|---|---|
| 80/tcp | HTTP | prod-lab — redirige vers 443 | [`nginx/sites-available/secure-web-lab-prod.conf`](../nginx/sites-available/secure-web-lab-prod.conf) |
| 443/tcp | HTTPS | prod-lab | idem |
| 8080/tcp | HTTP | dev — redirige vers 8443 | [`nginx/sites-available/secure-web-lab-dev.conf`](../nginx/sites-available/secure-web-lab-dev.conf) |
| 8443/tcp | HTTPS | dev | idem |
| 8081/tcp | HTTP | staging — redirige vers 8444 | [`nginx/sites-available/secure-web-lab-staging.conf`](../nginx/sites-available/secure-web-lab-staging.conf) |
| 8444/tcp | HTTPS | staging | idem |

Chaque port correspond exactement à un `listen` déclaré dans un des trois
vhosts Nginx du lab — aucun port ouvert "au cas où". Une évolution des
vhosts (ajout/suppression d'un port d'écoute) doit s'accompagner de la
mise à jour de ces règles ufw, sinon le firewall bloque un port pourtant
utilisé, ou en laisse un ouvert pour rien.

## Délibérément non ouvert : SSH (22/tcp)

Aucun serveur SSH n'est utilisé pour administrer cette machine — l'accès
se fait directement via `wsl.exe`/l'intégration WSL de VS Code, pas par le
réseau. Ouvrir 22/tcp par défaut "au cas où" irait contre le principe
appliqué ici (n'exposer que ce qui sert réellement) ; si un accès SSH
distant devient nécessaire, ajouter la règle à ce moment-là, avec la même
rigueur (idéalement restreinte par IP source plutôt qu'ouverte à tout le
réseau).

## Script

[`scripts/setup-firewall.sh`](../scripts/setup-firewall.sh) — idempotent
(installe `ufw` si absent, les règles `allow`/`default` ne dupliquent pas
en cas de ré-exécution), active `ufw` sans prompt interactif
(`--force enable`, nécessaire car `ufw enable` demande normalement une
confirmation qui bloquerait un script non interactif).

```bash
./scripts/setup-firewall.sh
```

## Vérification

```bash
sudo ufw status verbose
```

Exécuté (WSL2 Ubuntu 24.04 dédiée, voir
[`Notes/nginx/installation/README.md`](../Notes/nginx/installation/README.md)) :

```text
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), disabled (routed)
New profiles: skip

To                         Action      From
--                         ------      ----
80/tcp                     ALLOW IN    Anywhere                   # prod-lab HTTP (redirect vers HTTPS)
443/tcp                    ALLOW IN    Anywhere                   # prod-lab HTTPS
8080/tcp                   ALLOW IN    Anywhere                   # dev HTTP (redirect vers HTTPS)
8443/tcp                   ALLOW IN    Anywhere                   # dev HTTPS
8081/tcp                   ALLOW IN    Anywhere                   # staging HTTP (redirect vers HTTPS)
8444/tcp                   ALLOW IN    Anywhere                   # staging HTTPS
80/tcp (v6)                ALLOW IN    Anywhere (v6)              # prod-lab HTTP (redirect vers HTTPS)
443/tcp (v6)               ALLOW IN    Anywhere (v6)              # prod-lab HTTPS
8080/tcp (v6)              ALLOW IN    Anywhere (v6)              # dev HTTP (redirect vers HTTPS)
8443/tcp (v6)              ALLOW IN    Anywhere (v6)              # dev HTTPS
8081/tcp (v6)              ALLOW IN    Anywhere (v6)              # staging HTTP (redirect vers HTTPS)
8444/tcp (v6)              ALLOW IN    Anywhere (v6)              # staging HTTPS
```

Deux points à noter, ni l'un ni l'autre demandés explicitement par le
script :

- **Doublon IPv4/IPv6 automatique** — chaque `ufw allow <port>/tcp`
  génère une règle pour les deux piles ; aucune règle IPv6 séparée à
  écrire à la main.
- **`Logging: on (low)`** — activé par défaut par ufw dès l'activation, pas
  par une option du script. Suffisant pour voir les paquets bloqués dans
  `/var/log/ufw.log`, mais la journalisation détaillée (niveau, rotation,
  corrélation avec les logs Nginx) reste un sujet à part entière — voir
  Phase 2 : « journalisation avancée ».

## Limite connue : portée réelle sous WSL2

Le filtrage ufw s'applique au sein du namespace réseau de la VM WSL2, pas
directement à l'interface réseau physique de la machine hôte Windows —
voir [`Notes/ufw/reseau-wsl2-et-portee-du-filtrage.md`](../Notes/ufw/reseau-wsl2-et-portee-du-filtrage.md)
pour le détail. Sur ce lab (pas exposé à Internet), la valeur de cette
étape est avant tout de pratiquer la discipline de configuration
(default-deny explicite, ports documentés un par un) plutôt que de bloquer
un trafic hostile réel.
