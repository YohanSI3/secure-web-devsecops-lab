# Piège : `ssl_protocols` fusionne au lieu de remplacer

## Symptôme observé

Au premier déploiement, `nginx -t` a affiché :

```text
nginx: [warn] duplicate value "TLSv1.2" in /etc/nginx/conf.d/security.conf:12
nginx: [warn] duplicate value "TLSv1.3" in /etc/nginx/conf.d/security.conf:12
```

Non bloquant (`test is successful` quand même), donc facile à ignorer — à
tort : le warning révélait que la configuration TLS réellement appliquée
n'était pas celle voulue.

## Cause

`/etc/nginx/nginx.conf` (fichier stock du paquet Debian/Ubuntu, non
versionné dans ce dépôt) déclare déjà, par défaut :

```nginx
ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3; # Dropping SSLv3, ref: POODLE
```

`ssl_protocols` avait été ajouté dans `nginx/conf.d/security.conf`
(`ssl_protocols TLSv1.2 TLSv1.3;`), chargé automatiquement au même niveau
`http` que la ligne ci-dessus (`conf.d/*.conf` est inclus à l'intérieur du
bloc `http`). Or `ssl_protocols` fait partie d'une catégorie particulière
de directives nginx (`ngx_conf_set_bitmask_slot`, "directive bitmask") qui,
déclarées **plusieurs fois au même niveau de contexte**, ne se remplacent
pas : elles s'additionnent (fusion bit à bit). La plupart des directives
nginx suivent la règle inverse — la dernière déclaration au même niveau
écrase la précédente — ce qui rendait ce comportement contre-intuitif et
facile à mal supposer.

Conséquence concrète : la seconde déclaration (`TLSv1.2 TLSv1.3`)
s'ajoutait à la première (`TLSv1 TLSv1.1 TLSv1.2 TLSv1.3`) sans rien
retirer. Le site continuait donc, malgré la config du dépôt, à accepter
TLSv1.0 et TLSv1.1, deux protocoles obsolètes et vulnérables (dépréciés
officiellement par l'IETF en 2021 — RFC 8996).

## Correction

`ssl_protocols` a été déplacé du niveau `http` (`conf.d/security.conf`) au
niveau `server`, dans un nouveau snippet
([`nginx/snippets/tls-hardening.conf`](../../../nginx/snippets/tls-hardening.conf))
inclus dans chaque server block HTTPS. L'héritage de configuration nginx
suit une autre règle entre deux niveaux **différents** (parent/enfant) : si
le niveau enfant (`server`) déclare explicitement une valeur, celle-ci
remplace entièrement la valeur héritée du parent (`http`) — le mécanisme de
fusion additive ne s'applique qu'entre déclarations d'un même niveau, pas
entre parent et enfant. Placer `ssl_protocols TLSv1.2 TLSv1.3;` dans
chaque `server` produit donc bien le résultat voulu : uniquement TLSv1.2 et
TLSv1.3 acceptés, sans trace de TLSv1/1.1.

## Leçon générale

Un warning nginx non bloquant n'est pas nécessairement sans conséquence —
`nginx -t` valide la syntaxe, pas l'intention. Vérifier le comportement
réellement appliqué reste nécessaire même quand la configuration "semble"
correcte et que le test de syntaxe passe.

## Vérification : distinguer un refus client d'un refus serveur

Premier essai de vérification :

```bash
openssl s_client -connect 127.0.0.1:443 -servername secure-web-lab.local -tls1_1
```

Résultat : erreur immédiate `no protocols available`, **avant** même
l'établissement de la connexion TCP. Ce message vient du **client**
OpenSSL, pas du serveur : OpenSSL 3.0 applique par défaut un niveau de
sécurité (`SECLEVEL`) qui interdit lui-même TLSv1.0/1.1 côté client. Ce
premier test ne prouve donc rien sur la configuration du serveur — il
aurait échoué de la même façon même si nginx acceptait encore TLSv1.1.

Pour un test concluant, il faut forcer le client à quand même tenter la
négociation, en abaissant temporairement son propre niveau de sécurité :

```bash
openssl s_client -connect 127.0.0.1:443 -servername secure-web-lab.local \
  -tls1_1 -cipher 'DEFAULT@SECLEVEL=0'
```

Résultat obtenu : `tlsv1 alert protocol version` — cette fois l'erreur
survient bien après l'envoi du ClientHello et provient du **serveur**, qui
rejette explicitement la version de protocole proposée. C'est la
confirmation recherchée. Généralisable : quand un test de sécurité échoue
"trop facilement" ou "trop tôt", vérifier que l'échec vient bien du
composant testé et non d'une protection équivalente côté outil de test.
