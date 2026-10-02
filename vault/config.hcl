# Configuration Vault de ce lab -- déployée par scripts/deploy-vault-config.sh
# vers /etc/vault.d/vault.hcl. Voir vault/README.md pour le détail de
# chaque choix.

storage "file" {
  path = "/opt/vault/data"
}

# Boucle locale uniquement, comme PostgreSQL et le backend Node -- voir
# vault/README.md#tls pour pourquoi tls_disable ici précisément (même
# raisonnement que pour la connexion Node -> PostgreSQL).
listener "tcp" {
  address     = "127.0.0.1:8200"
  tls_disable = true
}

api_addr = "http://127.0.0.1:8200"

# Interface web activée : jamais exposée au-delà de 127.0.0.1 (même accès
# que l'API elle-même), utile pour explorer visuellement les secrets
# engines/policies pendant l'apprentissage -- voir vault/README.md.
ui = true
