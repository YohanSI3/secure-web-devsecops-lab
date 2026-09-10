# Portée réelle du filtrage ufw sous WSL2

## Le modèle réseau WSL2

WSL2 fait tourner Linux dans une véritable machine virtuelle légère (contrairement
à WSL1, qui traduisait les appels système sans noyau Linux réel). Cette VM
a sa propre interface réseau virtuelle, reliée à Windows via un commutateur
virtuel (`vEthernet (WSL)`), avec sa propre adresse IP côté Linux, distincte
de celle de la machine Windows hôte sur le réseau physique/local. Windows
agit en NAT devant cette VM : par défaut, une connexion venant du réseau
local ou d'Internet n'atteint pas directement WSL2, elle doit d'abord
atteindre Windows.

## Ce que ufw filtre réellement ici

Les règles posées par `scripts/setup-firewall.sh` s'appliquent au
netfilter du noyau **Linux de la VM WSL2** — donc à tout paquet qui arrive
jusqu'à cette interface réseau virtuelle. Elles filtrent :

- le trafic venant d'un **autre programme Windows** sur la même machine
  (ex. un navigateur qui viserait `localhost:8443`, transmis à la VM via le
  mécanisme de *localhost forwarding* de WSL2) ;
- tout trafic qui proviendrait effectivement du réseau local si un jour la
  VM était rendue accessible depuis l'extérieur (selon le mode réseau WSL —
  NAT par défaut, ou *mirrored networking* sur les versions récentes de
  WSL, qui rapproche davantage le comportement réseau de Linux de celui de
  Windows).

Elles ne remplacent pas, et n'ont aucune autorité sur, le pare-feu Windows
lui-même (Windows Defender Firewall) : ce dernier reste la première ligne
vue depuis l'extérieur de la machine Windows. Sur une installation WSL2
par défaut (NAT), la VM n'est de toute façon pas directement joignable
depuis Internet sans configuration additionnelle côté Windows (`netsh
interface portproxy`, ou mode réseau *mirrored*) — la surface réellement
exposée à un attaquant externe est donc déjà quasi nulle avant même
d'activer ufw.

## Pourquoi le faire quand même

Ce lab n'a pas vocation à rester sous WSL2 en pratique : la démarche
(politique default-deny, ports listés un par un, documentés et justifiés)
est celle qui compte, transférable telle quelle à un vrai serveur exposé
(VM cloud, machine physique) où elle aurait, elle, un effet de sécurité
direct contre du trafic hostile réel. Configurer et vérifier ufw ici sert
donc surtout à pratiquer correctement la démarche et à garder le dépôt
reproductible sur une cible qui, elle, sera réellement exposée — cohérent
avec l'objectif de reproductibilité déjà documenté dans
[`Notes/nginx/installation/README.md`](../nginx/installation/README.md).

Point de vigilance pour une bascule future vers une vraie machine exposée :
revérifier à ce moment-là qu'aucune règle ufw ne suppose implicitement le
NAT de WSL2 (aucune ici pour l'instant — les règles ne référencent que des
ports, pas des plages d'adresses spécifiques à ce réseau virtuel).
