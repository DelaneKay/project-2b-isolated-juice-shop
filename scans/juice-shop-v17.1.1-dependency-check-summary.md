# OWASP Juice Shop SCA Report

## Scope and method

- **Target:** `bkimminich/juice-shop:v17.1.1` container image.
- **Scanner:** OWASP Dependency-Check 13.0.0, run from `owasp/dependency-check:latest` on the private scanner EC2 instance.
- **Scan date:** 2026-10-26 19:41 UTC.
- **Scan input:** application filesystem copied from the pinned image, including its installed `node_modules`, then mounted read-only into Dependency-Check.
- **Vulnerability data:** Dependency-Check Builder's hosted NVD cache feed. The direct NVD API key supplied during troubleshooting was rejected, so the successful scan used the cache feed without an API key. The report records the feed's last-modified time as 2026-10-26 17:13:18 UTC.
- **Raw report:** `juice-shop-v17.1.1-dependency-check-report.html` (35 MB), retained in the WSL project's `scans/` directory.

## Results

| Measure | Result |
| --- | ---: |
| Dependency records scanned | 17,799 |
| Unique dependencies | 13,484 |
| Vulnerable dependency records | 115 |
| Vulnerability associations reported | 513 |
| Distinct CVE identifiers present in the HTML report | 259 |
| Suppressed vulnerabilities | 0 |

The following counts are **vulnerable dependency records grouped by their highest reported severity**, not counts of individual CVEs:

| Highest severity | Dependency records |
| --- | ---: |
| Critical | 29 |
| High | 48 |
| Medium or Moderate | 33 |
| Low | 5 |

Notable npm package matches by reported CVE count include:

| Package/version | Highest severity | CVE count |
| --- | --- | ---: |
| `vm2@3.9.17` | Critical | 79 |
| `handlebars@4.7.7` | Critical | 17 |
| `@xmldom/xmldom@^0.8.5` | High | 15 |
| `tar@4.4.19` | High | 12 |
| `lodash@2.4.2` | Critical | 11 |
| `sanitize-html@1.4.2` | High | 10 |
| `jsonwebtoken@0.4.0` | Critical | 8 |
| `nanoid@3.1.20` | High | 8 |
| `decompress@4.2.1` | Critical | 7 |

## Interpretation and limitations

Juice Shop is intentionally vulnerable. These findings establish an SCA baseline for the selected image; they are not, by themselves, proof that every listed CVE is exploitable in this deployment. Dependency-Check uses best-effort package identification and CPE matching, so false positives and false negatives are possible. Repeated bundled JavaScript artifacts can also produce duplicate-looking matches; validate package identity, affected version ranges, and runtime reachability before treating individual matches as confirmed risks.

The scan completed and wrote the HTML report. The logs showed repeated warnings about unsupported CVSS vector formats in npm audit results; the Node Audit Analyzer nevertheless completed. The Sonatype OSS Index analyzer was disabled because no Sonatype Guide credentials were configured. Thus these results do not include an OSS Index assessment. No vulnerability suppressions were applied.

The cache feed is a convenient alternative for this lab, but its freshness depends on the feed publisher's update cadence. Record the scan timestamp and cache timestamp when comparing future runs. For a production pipeline, use an approved, maintained data source and a stable, explicitly pinned Dependency-Check image version rather than relying on the mutable `latest` tag.

## Recommended lab follow-up

1. Preserve this report as the baseline for the exact Juice Shop image tag.
2. Review the Critical and High matches in the HTML report, starting with the packages listed above; confirm each package/version and affected CVE range.
3. Keep this vulnerable target isolated. Do not treat the scan as a pass/fail gate for Juice Shop itself; use it to demonstrate SCA findings, validation, prioritization, and evidence capture.
4. Keep SCA separate from the completed SonarQube SAST and Nuclei DAST results; all three are summarized in [`../docs/security-assessment.md`](../docs/security-assessment.md).
