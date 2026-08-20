# Headers de sécurité de base

## Contexte

Suite (et dernier point) de la Phase 1 du `ToDo.md` : "headers de sécurité
de base" + "désactivation d'informations inutiles". Fait dans la foulée du
TLS local (`Notes/nginx/tls/`) car certains headers (HSTS) n'ont de sens
qu'une fois HTTPS disponible.

- [`en-tetes-expliques.md`](en-tetes-expliques.md) — chaque header
  ajouté, son rôle, ce qu'il empêche concrètement.
- [`snippets-et-confd.md`](snippets-et-confd.md) — pourquoi cette
  configuration est centralisée dans `nginx/snippets/` et
  `nginx/conf.d/` plutôt que répétée dans chaque fichier de site.

## Ce qui a été fait

- [`nginx/snippets/security-headers.conf`](../../../nginx/snippets/security-headers.conf)
  — headers communs aux trois environnements, inclus dans chaque server
  block HTTPS.
- [`nginx/conf.d/security.conf`](../../../nginx/conf.d/security.conf)
  — `server_tokens off;` (déjà présent en commentaire dans la config nginx
  par défaut d'Ubuntu, activé ici) + `ssl_protocols`.
- Page statique : CSS externalisé dans
  [`app/static-site/style.css`](../../../app/static-site/style.css)
  plutôt qu'en `<style>` inline, requis par la CSP appliquée (voir
  `en-tetes-expliques.md`).

## Vérification

```bash
curl -skI --resolve secure-web-lab.local:443:127.0.0.1 \
  https://secure-web-lab.local/ | grep -iE \
  'strict-transport|x-content-type|x-frame|referrer-policy|content-security|permissions-policy|^server:'
```

`Server:` doit afficher `nginx` sans numéro de version (`server_tokens
off;`), et chaque header de sécurité doit être présent.
