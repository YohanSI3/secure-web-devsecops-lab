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
- désactivation méthodes inutiles,
- rate limiting,
- contrôle des tailles de requêtes,
- timeouts adaptés,
- protection contre divulgation de version,
- journalisation avancée,
- rotation de logs.

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
- rules de merge minimales.

#### *Phase 4:*
- .env.example sans secrets réels,
- secrets GitHub pour CI,
- Vault,
- rotation simulée,
- séparation secret applicatif / infra / CI,
- politique de non-commit des secrets,
- détection automatique,

#### *Phase 5:*
- dashboards simples,
- logs centralisés,
- alertes basiques,
- surveillance des erreurs HTTP,
- suivi des IP suspectes,
- détection de pics de requêtes,
- corrélation simple avec scans.

#### *Phase 6:*
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
│   └── static-site/
└── .env.example
```


