# Sanitized assessment reports and evidence only.
# Never store credentials, private keys, tokens, or real customer data here.

## OWASP Dependency-Check — Juice Shop v17.1.1

- Raw HTML: `juice-shop-v17.1.1-dependency-check-report.html` (about 35 MB).
- Review summary: `juice-shop-v17.1.1-dependency-check-summary.md`.
- Target: `bkimminich/juice-shop:v17.1.1`; scanner: Dependency-Check 13.0.0.
- Generated: 2026-10-26 19:41 UTC. The scan used the Dependency-Check Builder hosted NVD cache feed.
- Results: 17,799 dependency records scanned; 115 vulnerable dependency records; 513 vulnerability associations; 0 suppressions.

Juice Shop is intentionally vulnerable. Treat this as a lab baseline, validate individual matches, and review the report for environment-specific details before publishing it.

## SonarQube — SAST

- Curated dashboard/findings workbook: `sonarqube-juice-shop-findings.xlsx`.
- The project overview showed a passed quality gate, with 127 Security (E), 132 Reliability (D), and 605 Maintainability (A) issues in Overall Code.
- The workbook is a curated summary, not a full SonarQube issue export. Analysis warnings and representative issue excerpts are documented in [`../docs/security-assessment.md`](../docs/security-assessment.md).

## Nuclei — DAST

- Target: private Juice Shop at `http://10.30.20.52:3000`.
- Scanner: Nuclei v3.11.1 on the private scanner EC2 host.
- One informational Swagger API-documentation endpoint was found. See [`nuclei/`](nuclei/) and the full assessment for limitations.

## Completed versus planned

Dependency-Check, SonarQube, and Nuclei runs are documented. Trivy and OWASP ZAP were not completed in this lab run and have no retained reports.
