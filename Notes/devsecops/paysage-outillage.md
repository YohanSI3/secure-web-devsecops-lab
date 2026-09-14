# Paysage de l'outillage DevSecOps : gratuit ici, payant dans l'industrie

Ce lab n'utilise que des outils gratuits/open source — par choix
(reproductibilité sans compte ni licence à gérer) et par contrainte (pas
de budget pour un projet personnel). En pratique, une bonne partie de
l'industrie utilise des versions commerciales de ces mêmes catégories
d'outils, avec des fonctionnalités supplémentaires (tableaux de bord
centralisés multi-dépôts, remédiation automatique assistée, support,
conformité réglementaire). Repère utile pour se situer dans ce qui se
fait "en vrai" — à explorer par soi-même plutôt qu'à intégrer ici.

| Catégorie | Implémenté dans ce lab | Référence(s) commerciale(s) à connaître |
|---|---|---|
| SAST | [Semgrep OSS](https://semgrep.dev) (rulesets publics) | Semgrep Code (offre payante, règles propriétaires + gestion centralisée), Snyk Code, Checkmarx, Veracode |
| SAST (natif GitHub) | *non activé ici* — [CodeQL](https://codeql.github.com) est gratuit sur dépôt public, mais ne couvre que des langages applicatifs (JS, Python, Java, Go, C/C++, C#, Ruby, Swift) : rien de tel dans ce dépôt (bash/config/Markdown) pour l'instant | GitHub Advanced Security (CodeQL + secret scanning avancé, payant sur dépôt **privé**) |
| Secrets scanning | [gitleaks](https://github.com/gitleaks/gitleaks) + push protection GitHub (native, gratuite sur dépôt public) | GitGuardian (détection + gestion d'incidents, surveillance au-delà de GitHub), Push protection GitHub sur dépôt **privé** (payant via GitHub Advanced Security) |
| SCA (dépendances) | [Dependabot](https://docs.github.com/en/code-security/dependabot) (natif GitHub, gratuit) | Snyk Open Source, Mend (ex-WhiteSource), JFrog Xray |
| Lint config Nginx | [gixy](https://github.com/yandex/gixy) | — (pas d'équivalent commercial dédié notable ; ce segment reste surtout open source) |
| CI/CD | [GitHub Actions](https://github.com/features/actions) (gratuit, quotas généreux sur dépôt public) | GitLab CI Ultimate, CircleCI, Jenkins (auto-hébergé, gratuit mais coût d'exploitation) |
| DAST | *non implémenté ici* (voir [`sast-dast-sca.md`](sast-dast-sca.md)) | OWASP ZAP (gratuit, référence open source), Burp Suite Enterprise, Invicti |
| Gestion de secrets (au runtime, pas au scan) | *prévu Phase 4 du `ToDo.md`* | HashiCorp Vault (aussi disponible en open source, la version Enterprise est payante), AWS Secrets Manager, Azure Key Vault |
| Observabilité / SIEM (Phase 5) | *non traité à ce stade* | Splunk, Datadog Security, Elastic Security (aussi open source à la base) |
| Scan IaC (si Docker/Terraform ajoutés) | *non applicable pour l'instant* | Checkov (gratuit), tfsec (gratuit), Snyk IaC, Prisma Cloud |

## Une nuance à garder : "gratuit" et "open source" ne sont pas synonymes

Plusieurs outils cités existent en **deux offres** : un cœur open source
librement utilisable (parfois auto-hébergeable), et une couche
commerciale par-dessus (hébergement géré, tableau de bord centralisé,
fonctionnalités entreprise). Semgrep, gitleaks-adjacent (GitGuardian n'a
pas de version gratuite équivalente, à l'inverse), Vault, et Elastic
Security en sont des exemples typiques — le choix « gratuit » fait ici
correspond à la version communautaire de l'outil, pas nécessairement à
l'absence totale d'offre payante pour ce même nom.
