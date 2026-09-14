# Plan général et suivi du projet.

### **Objectifs:**
- concevoir proprement,
- documenter,
- approche sécurité by design,
- tests dans un cadre maîtrisé,
- infrastructure + automatisation + sécurité.

### **Configuration initial:**
- Serveur web principal: Nginx.
- Objectif initial: reverse proxy + serveur web sécurisé.
- Environnement: Linux.
- Approche: progressive, documentée, sécurisée par design.

### **Sur Nginx, travail sur:**
- configuration propre,
- hardening,
- erreurs fréquentes de sécurité,
- exposition réseau,
- mauvaises pratiques de secrets,
- traçabilité,
- automatisation sécurisée.

### **Idées de phases d'intégrations (non fixé, implémentation en fonction du besoin):**

#### *Phase 1:*
- installation Nginx,
- page web statique simple,
- configuration Nginx versionnée,
- séparation dev / staging / prod-lab,
- TLS local ou lab,
- logs d’accès et d’erreurs,
- headers de sécurité de base,
- désactivation d’informations inutiles,
- arborescence de configuration claire.

#### *Phase 2:*
- utilisateur dédié,
- permissions minimales,
- firewall,
- fail2ban ou équivalent,
- configuration TLS propre,
- rate limiting,
- contrôle des tailles de requêtes,
- timeouts adaptés,
- protection contre divulgation de version,
- journalisation avancée,
- rotation de logs,
- une fois l'application développée (voir Phase 5, IAM) : gestion de
  données sensibles côté application (mots de passe, sessions, tokens),
  pas seulement côté infrastructure.

#### *Phase 3:*
- dépôt Git propre,
- branches protégées,
- CI,
- lint config Nginx,
- scan SAST,
- scan secrets,
- scan dépendances,
- scan IaC si tu ajoutes Docker/Terraform/Ansible,
- artefacts de build contrôlés,
- rules de merge minimales,
- une fois l'application développée (voir Phase 5, IAM) : SAST et scan de
  dépendances sur du vrai code applicatif avec un vrai gestionnaire de
  paquets, pas seulement sur des scripts bash et de la config.

#### *Phase 4:*
- .env.example sans secrets réels,
- secrets GitHub pour CI,
- Vault,
- rotation simulée,
- séparation secret applicatif / infra / CI,
- politique de non-commit des secrets,
- détection automatique,
- une fois l'application développée (voir Phase 5, IAM) : vrais secrets
  applicatifs à gérer (clé de signature de session/JWT, éventuel secret
  de hachage, identifiants de connexion à la base de données).

#### *Phase 5 (IAM):*
- application développée avec un vrai backend (Node.js + Express,
  PostgreSQL, Nginx en reverse proxy devant) pour porter
  l'authentification, plus seulement du statique — auth construite à la
  main dans l'app (pas de service d'identité tiers type Keycloak pour
  l'instant, envisageable comme évolution plus tard),
- identification : inscription / création de compte,
- authentification : mots de passe hachés (jamais en clair ni
  réversible), gestion de session ou tokens, option MFA,
- autorisation : permissions par rôle (RBAC), séparation utilisateur
  standard / admin,
- protections dédiées : limitation des tentatives de connexion,
  résistance à l'énumération de comptes, réinitialisation de mot de passe
  sécurisée,
- traçabilité : journal des actions sensibles (connexion, changement de
  permission, etc.),
- ce que ça débloque : données sensibles réelles à protéger (Phase 2),
  vrai code à scanner (Phase 3), vrais secrets applicatifs à gérer
  (Phase 4).

#### *Phase 6:*
- dashboards simples,
- logs centralisés,
- alertes basiques,
- surveillance des erreurs HTTP,
- suivi des IP suspectes,
- détection de pics de requêtes,
- corrélation simple avec scans.

#### *Phase 7:*
- scans basiques de configuration,
- vérification TLS,
- fuzz léger sur endpoints de lab,
- tests d’exposition de headers,
- tests de mauvaises confs volontaires dans un environnement isolé,
- documentation “misconfig -> impact -> remédiation”.


## **Achitecture possible:**

```text
secure-web-devsecops-lab/
├── README.md
├── docs/
│   ├── architecture.md
│   ├── hardening.md
│   ├── threat-model.md
│   └── roadmap.md
├── nginx/
│   ├── nginx.conf
│   ├── conf.d/
│   ├── sites-available/
│   └── snippets/
├── infra/
│   ├── docker/
│   ├── ansible/
│   └── terraform/
├── security/
│   ├── baselines/
│   ├── scans/
│   └── policies/
├── .github/
│   └── workflows/
├── app/
│   ├── static-site/      # front, existant
│   └── backend/          # à venir (Phase 5, IAM) : Node.js + Express,
│                         # PostgreSQL, auth maison (hash, sessions/JWT, RBAC)
└── .env.example
```


