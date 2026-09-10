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

## Action de bannissement : `iptables-multiport` (défaut), pas `ufw`

fail2ban propose une action `banaction = ufw` toute prête. Volontairement
**pas utilisée ici** : cette action shippée s'appuie sur les *profils
d'application* ufw (`ufw allow "Nginx Full"`, `ufw allow OpenSSH` — des
noms enregistrés dans `/etc/ufw/applications.d/`), alors que
[`scripts/setup-firewall.sh`](../scripts/setup-firewall.sh) autorise des
ports bruts (`ufw allow 8443/tcp`), sans profil d'application déclaré. Une
jail avec `banaction = ufw` telle quelle référencerait un profil
inexistant et échouerait silencieusement à bannir quoi que ce soit.

`jail.local` ne fixe donc pas `banaction` et hérite du défaut de
`/etc/fail2ban/jail.conf` : `iptables-multiport`. Cette action insère ses
propres règles `DROP` dans une chaîne dédiée (`f2b-<jail>`), indépendante
des chaînes gérées par ufw — les deux coexistent sans conflit, chacun gère
ses propres règles dans netfilter. Point à revérifier si une future
version de ce dépôt enregistre des profils d'application ufw : la bascule
vers `banaction = ufw` deviendrait alors possible et plus lisible
(`ufw status` montrerait aussi les IP bannies par fail2ban).

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

## Tester manuellement `nginx-404-flood`

```bash
for i in $(seq 1 12); do
  curl -sk -o /dev/null --resolve dev.secure-web-lab.local:8443:127.0.0.1 \
    "https://dev.secure-web-lab.local:8443/inexistant-$i"
done

sudo fail2ban-client status nginx-404-flood
```

**Attention** : ce test bannit réellement l'IP source (ici la propre
machine de test) sur les 6 ports du lab pendant 1h. Pour débannir sans
attendre :

```bash
sudo fail2ban-client set nginx-404-flood unbanip <ip>
```

## Vérification

```bash
sudo fail2ban-client status
sudo fail2ban-client status nginx-botsearch
sudo fail2ban-client status nginx-404-flood
```

*(sortie réelle à ajouter ici après exécution)*
