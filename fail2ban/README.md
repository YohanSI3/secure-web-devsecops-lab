# fail2ban

Documentation technique de fail2ban pour ce lab — ce qui est réellement
configuré et pourquoi. Pour le fonctionnement général (jails, filtres,
actions, comment fail2ban détecte puis agit), voir
[`Notes/fail2ban/`](../Notes/fail2ban/README.md).

## Jails activées

| Jail | Filtre | Source | Seuil | Ban |
|---|---|---|---|---|
| `nginx-botsearch` | livré avec fail2ban | logs des 3 vhosts | défaut du filtre | 1h |
| `nginx-404-flood` | [`filter.d/nginx-404-flood.conf`](filter.d/nginx-404-flood.conf) (custom) | logs des 3 vhosts | 10 requêtes 404 / 5 min | 1h |
| `sshd` | livré avec fail2ban | — | — | désactivée explicitement |

`nginx-botsearch` couvre les scans génériques classiques (recherche de
`wp-login.php`, `.env`, `phpmyadmin`, etc.) indépendamment du contenu réel
du site — pertinent même sans aucune application dynamique derrière Nginx.

`nginx-404-flood` est un filtre écrit pour ce lab précisément, absent des
filtres livrés avec fail2ban : [`app/static-site/`](../app/static-site/)
ne sert que deux fichiers (`index.html`, `style.css`) via
`try_files $uri $uri/ =404;` (voir
[`Notes/nginx/configuration/server-block-directives.md`](../Notes/nginx/configuration/server-block-directives.md)).
Sur un site à surface aussi réduite, toute 404 répétée depuis la même IP
est un signal d'énumération quasiment sans faux positif — contrairement à
un site avec beaucoup de pages légitimes, où un taux de 404 modéré est
normal (liens cassés, favicons, etc.).

Les deux jails pointent sur `/var/log/nginx/secure-web-lab-*.access.log`
(glob couvrant dev/staging/prod en une seule jail plutôt que trois jails
dupliquées) et sur `port = 80,443,8080,8443,8081,8444` — exactement les
ports déclarés dans [`firewall/README.md`](../firewall/README.md). Toute
évolution des ports des vhosts doit être répercutée aux **deux** endroits
(`fail2ban/jail.local` et les règles ufw), sinon une IP bannie reste
capable d'atteindre un port omis.

## Découvert à l'exécution : jail `sshd` activée par défaut

Le paquet `fail2ban` d'Ubuntu embarque
`/etc/fail2ban/jail.d/defaults-debian.conf`, qui active `[sshd]` par
défaut (protection SSH prête à l'emploi hors de toute config de ce dépôt).
Sans rapport avec `nginx-botsearch`/`nginx-404-flood`, mais incohérent
avec ce lab : aucun `sshd` n'écoute sur cette machine (accès WSL direct,
pas par le réseau — même décision déjà prise dans
[`firewall/README.md`](../firewall/README.md#délibérément-non-ouvert--ssh-22tcp)
pour ne pas ouvrir le port 22). `jail.local` charge après
`jail.d/defaults-debian.conf`, donc y ajouter `[sshd]` / `enabled = false`
suffit à neutraliser ce défaut du paquet — fait dans
[`jail.local`](jail.local).

## Bug réel découvert à l'exécution : les jails ne voyaient jamais rien

Après activation, `nginx-botsearch` et `nginx-404-flood` restaient à
`Currently failed: 0` même après une requête réelle vers `/wp-login.php`
qui, elle, apparaissait bien dans le fichier de log et matchait le filtre
en test isolé (`fail2ban-regex <fichier> <filtre>` → `1 matched`). Le
filtre n'était donc pas en cause.

Cause trouvée dans `/var/log/fail2ban.log` :
`fail2ban.filtersystemd [...]: INFO [nginx-botsearch] Jail is in
operation now (process new journal entries)` — les deux jails tournaient
en réalité sur le **backend `systemd`** (lecture du journal), pas sur nos
fichiers `logpath` : `sudo fail2ban-client get nginx-botsearch logpath`
répondait `No file is currently monitored`, confirmant qu'aucun fichier
n'était surveillé. Or Nginx écrit ses logs directement dans les fichiers
`access_log`/`error_log` (voir
[`Notes/nginx/configuration/logs-et-privileges.md`](../Notes/nginx/configuration/logs-et-privileges.md)),
jamais dans le journal systemd — les deux jails ne pouvaient donc
structurellement rien détecter, quel que soit le trafic réel.

Racine du problème : le même `/etc/fail2ban/jail.d/defaults-debian.conf`
que pour `sshd` ci-dessus fixe aussi `backend = systemd` au niveau
`[DEFAULT]` du paquet Ubuntu. `jail.local` ne surchargeait pas `backend`
explicitement, donc nos jails héritaient de ce `systemd` au lieu du défaut
`auto` de `jail.conf` (qui, lui, aurait correctement choisi un backend
fichier). **Corrigé** en fixant `backend = pyinotify` explicitement au
niveau `[DEFAULT]` de [`jail.local`](jail.local) — `python3-pyinotify` est
déjà installé (dépendance tirée automatiquement par le paquet `fail2ban`
à l'installation).

## Action de bannissement : `nftables` (défaut réel du paquet Ubuntu), pas `ufw`

fail2ban propose une action `banaction = ufw` toute prête. Volontairement
**pas utilisée ici** : cette action shippée s'appuie sur les *profils
d'application* ufw (`ufw allow "Nginx Full"`, `ufw allow OpenSSH` — des
noms enregistrés dans `/etc/ufw/applications.d/`), alors que
[`scripts/setup-firewall.sh`](../scripts/setup-firewall.sh) autorise des
ports bruts (`ufw allow 8443/tcp`), sans profil d'application déclaré. Une
jail avec `banaction = ufw` telle quelle référencerait un profil
inexistant et échouerait silencieusement à bannir quoi que ce soit.

`jail.local` ne fixe donc pas `banaction`. **Correction** : la première
version de cette note affirmait qu'il héritait alors du défaut de
`/etc/fail2ban/jail.conf` (`iptables-multiport`) — faux, vérifié après
coup sur la machine réelle. Le paquet Ubuntu embarque
`/etc/fail2ban/jail.d/defaults-debian.conf`, chargé avant `jail.local`,
qui fixe `banaction = nftables` (et `banaction_allports = nftables[type=allports]`)
au niveau `[DEFAULT]` — c'est ce qui s'applique réellement ici, pas la
valeur de `jail.conf`. `nftables` cible directement des ports numériques
(pas de profil d'application nommé), donc pas le même problème que l'action
`ufw` : il fonctionne correctement avec les règles ufw à base de ports
bruts de ce lab. `ufw` et fail2ban gèrent chacun leurs propres tables/
chaînes nftables indépendantes — pas de conflit constaté.

Point d'attention retenu de cette correction : ne pas déduire un
comportement de `jail.conf` seul — `/etc/fail2ban/jail.d/*.conf` (livré par
le paquet de la distribution, pas par ce dépôt) peut redéfinir le
`[DEFAULT]` avant que `jail.local` ne s'applique. Toujours vérifier le
comportement réellement actif (`fail2ban-client get <jail> ...`, logs) au
lieu de ne lire que `jail.conf`.

## Script

[`scripts/setup-fail2ban.sh`](../scripts/setup-fail2ban.sh) : installe le
paquet si absent, relie `jail.local` et `filter.d/*.conf` dans
`/etc/fail2ban/` par symlink (même logique que
[`scripts/deploy-nginx-config.sh`](../scripts/deploy-nginx-config.sh) pour
Nginx), redémarre le service, puis fait tourner `fail2ban-regex` sur une
ligne de log synthétique pour valider que le filtre personnalisé matche
bien avant de compter sur un vrai comportement suspect pour le tester.

```bash
./scripts/setup-fail2ban.sh
```

## Tester manuellement : `ignoreself` et pourquoi `127.0.0.1` ne suffit pas

fail2ban ignore par défaut (`ignoreself = true`, réglage `[DEFAULT]` de
`jail.conf`) tout trafic dont la source est une adresse locale de la
machine elle-même (dont `127.0.0.1`) — protection pensée pour ne pas
s'auto-bannir en testant. Constaté à l'exécution :
`fail2ban.log` a bien montré le fichier correctement surveillé et la ligne
détectée, mais aussi `[nginx-botsearch] Ignore 127.0.0.1 by ignoreself
rule` : tester en ciblant `127.0.0.1` ne fera donc **jamais** apparaître de
`Currently failed`, quel que soit le nombre de requêtes envoyées — pas un
bug, un garde-fou qui s'applique avant même la logique de la jail.

Pour un test réel, cibler l'IP de l'interface réseau de la VM plutôt que
la boucle locale :

```bash
VM_IP="$(hostname -I | awk '{print $1}')"

for i in $(seq 1 12); do
  curl -sk -o /dev/null --resolve "dev.secure-web-lab.local:8443:${VM_IP}" \
    "https://dev.secure-web-lab.local:8443/inexistant-$i"
done

sudo fail2ban-client status nginx-404-flood
```

**Attention** : ce test bannit réellement l'IP source (ici l'IP de la
propre machine de test, mais plus la loopback exemptée) sur les 6 ports du
lab pendant 1h. Pour débannir sans attendre :

```bash
sudo fail2ban-client set nginx-404-flood unbanip <ip>
```

## Vérification

```bash
sudo fail2ban-client status
sudo fail2ban-client status nginx-botsearch
sudo fail2ban-client status nginx-404-flood
```

Exécuté (avant l'ajout de `[sshd] enabled = false` ci-dessus, d'où sa
présence dans cette sortie) :

```text
Status
|- Number of jail:      3
`- Jail list:   nginx-404-flood, nginx-botsearch, sshd
Status for the jail: nginx-botsearch
|- Filter
|  |- Currently failed: 0
|  |- Total failed:     0
|  `- Journal matches:  _SYSTEMD_UNIT=nginx.service + _COMM=nginx
`- Actions
   |- Currently banned: 0
   |- Total banned:     0
   `- Banned IP list:
Status for the jail: nginx-404-flood
|- Filter
|  |- Currently failed: 0
|  |- Total failed:     0
|  `- Journal matches:
`- Actions
   |- Currently banned: 0
   |- Total banned:     0
   `- Banned IP list:
```

`Currently failed: 0` / `Total failed: 0` semblaient à première vue
attendus juste après un redémarrage sans trafic suspect réel — mais un
test réel (requête vers `/wp-login.php`) est resté lui aussi à 0, ce qui a
mené à la découverte ci-dessus (« Bug réel découvert à l'exécution ») :
**cette sortie ne prouvait pas que la jail attendait simplement du
trafic, elle tournait sur le mauvais backend et n'aurait jamais rien vu.**
Le champ `Journal matches: _SYSTEMD_UNIT=nginx.service + _COMM=nginx`
affiché ici n'était donc pas une métadonnée inerte comme supposé dans une
version précédente de cette note, mais l'indication — passée inaperçue au
premier passage — que le backend actif était bien `systemd`. Après
correctif (`backend = pyinotify`) :

```bash
sudo fail2ban-client get nginx-botsearch logpath
```
```text
Current monitored log file(s):
|- /var/log/nginx/secure-web-lab-dev.access.log
|- /var/log/nginx/secure-web-lab-prod.access.log
`- /var/log/nginx/secure-web-lab-staging.access.log
```

Confirme le passage en surveillance de fichiers réels. Un nouveau test
avec `/wp-login.php` restait pourtant à `Currently failed: 0` — cette
fois pour une raison différente et attendue, pas un bug : la requête de
test venait de `127.0.0.1`, systématiquement ignorée par la règle
`ignoreself` de fail2ban (voir
[« Tester manuellement »](#tester-manuellement--ignoreself-et-pourquoi-127001-ne-suffit-pas)
ci-dessus pour le test corrigé, avec l'IP réelle de la VM). Bilan de cette
série de débogages : deux causes distinctes empilées (backend, puis
ignoreself) ont chacune produit le même symptôme (`Currently failed: 0`)
pour des raisons entièrement différentes — un rappel que le même
symptôme ne garantit pas la même cause, et qu'il faut vérifier chaque
couche (filtre isolé, backend/fichier surveillé, puis IP source) plutôt
que de s'arrêter à la première explication plausible.

Test corrigé (IP réelle de la VM, plus loopback) — 12 requêtes vers des
chemins inexistants sur `dev` :

```text
Status for the jail: nginx-404-flood
|- Filter
|  |- Currently failed: 1
|  |- Total failed:     12
|  `- File list:        /var/log/nginx/secure-web-lab-dev.access.log /var/log/nginx/secure-web-lab-prod.access.log /var/log/nginx/secure-web-lab-staging.access.log
`- Actions
   |- Currently banned: 1
   |- Total banned:     1
   `- Banned IP list:   172.23.201.189
```

Les 12 requêtes ont bien été comptées (`Total failed: 12`, seuil
`maxretry = 10` dépassé) et l'IP source a été bannie
(`Currently banned: 1`) — chaîne complète confirmée fonctionnelle :
détection par fichier de log → seuil → action `nftables`. `Currently
failed: 1` (et non 12) est normal : ce compteur retombe à 0 dès qu'un
bannissement est déclenché pour cette IP, seul `Total failed` reste
cumulatif.

`172.23.201.189` est l'adresse de l'interface réseau de la VM WSL2
elle-même (`hostname -I`) — désormais bannie sur les 6 ports du lab
pendant 1h. Pour débannir avant expiration :

```bash
sudo fail2ban-client set nginx-404-flood unbanip 172.23.201.189
```
