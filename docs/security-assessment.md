# Project 2B — Security Assessment and Scan Results

**Assessment date:** 2026-10-27  
**Target:** OWASP Juice Shop v17.1.1 on private EC2  
**Region:** `us-east-1`  
**Status:** Lab deployment destroyed after testing; scan artifacts retained locally.

**Last deployment host IDs:** Juice Shop app `i-0553f724dcdade47e` (`10.30.20.52`); scanner `i-03e2af14e0abfd20d` (`10.30.10.223`); SonarQube Spot host `i-0cde1554bd56e9859` (`10.30.10.52`). These are the final IDs before teardown and will change on redeployment.

## Executive summary

The lab deployed the intentionally vulnerable Juice Shop application on a private EC2 instance and used a separate private scanner instance. Operators connected with AWS Systems Manager (SSM); the scanner reached the application on TCP 3000. The application was not intentionally exposed to the public internet, and the project did not use AWS WAF because there was no public HTTP entry point to protect.

Three assessment activities produced evidence:

| Control area | Tool | Outcome |
| --- | --- | --- |
| Software composition analysis (SCA) | OWASP Dependency-Check 13.0.0 | Completed against the v17.1.1 image filesystem; 115 vulnerable dependency records and 259 distinct CVE identifiers were reported. |
| Static application security testing (SAST) | SonarQube Community Build 26.9.0 | Completed; quality gate passed. The dashboard showed 127 Security issues (E), 132 Reliability issues (D), and 605 Maintainability issues (A) in Overall Code. |
| Dynamic application security testing (DAST) | Nuclei 3.11.1 | Completed from the scanner host against the private app; one informational Swagger API documentation endpoint was found. |

These are baseline results for an intentionally vulnerable training application, not a production security certification. The SonarQube quality gate passing does not mean the application is secure: its dashboard still showed a substantial issue backlog. No remediation was performed as part of this baseline run.

## Scope and evidence

### SCA — OWASP Dependency-Check

Dependency-Check scanned the source filesystem extracted from the pinned `bkimminich/juice-shop:v17.1.1` image, including installed `node_modules`. The scan completed on 2026-10-26 at 19:41 UTC using Dependency-Check 13.0.0 and the hosted NVD cache feed. The direct NVD API key attempt was rejected; the successful report used cached data whose recorded last-modified time was 2026-10-26 17:13:18 UTC.

| Measure | Result |
| --- | ---: |
| Dependency records scanned | 17,799 |
| Unique dependencies | 13,484 |
| Vulnerable dependency records | 115 |
| Vulnerability associations | 513 |
| Distinct CVE identifiers | 259 |
| Suppressed vulnerabilities | 0 |

Highest reported severity per vulnerable dependency record: 29 Critical, 48 High, 33 Medium/Moderate, and 5 Low. The raw HTML report names `vm2@3.9.17` (79 CVE matches), `handlebars@4.7.7` (17), `@xmldom/xmldom@^0.8.5` (15), and `tar@4.4.19` (12), among other matches. These are scanner matches and require package/version and reachability validation before asserting exploitability. The report logs also warned that some npm audit CVSS vector formats were unsupported and that Sonatype OSS Index analysis was disabled for missing credentials.

**Evidence:** [`../scans/juice-shop-v17.1.1-dependency-check-report.html`](../scans/juice-shop-v17.1.1-dependency-check-report.html), [`../scans/juice-shop-v17.1.1-dependency-check-summary.md`](../scans/juice-shop-v17.1.1-dependency-check-summary.md).

### SAST — SonarQube

SonarQube analyzed the Juice Shop v17.1.1 project (approximately 54,000 lines of code). The project overview showed a **Passed** quality gate, with **127 Security issues rated E**, **132 Reliability issues rated D**, and **605 Maintainability issues rated A** in Overall Code. Those are SonarQube issue counts/ratings; they should not be restated as confirmed exploitable vulnerabilities.

The user-provided issue excerpts included examples from `frontend/src/app/about/about.component.ts` (Angular sanitizer/control guidance), form-label association, integrity/crossorigin attributes for an external resource in `frontend/src/index.html`, a test missing an assertion, cognitive complexity in `routes/order.ts`, and a `for-of` recommendation in `frontend/src/app/search-result/search-result.component.ts`. These are representative excerpts, not a complete issue export. The workbook [`../scans/sonarqube-juice-shop-findings.xlsx`](../scans/sonarqube-juice-shop-findings.xlsx) is a curated summary and is not the full SonarQube report.

Analysis warnings: Python version was not explicitly configured; `sonar.tests` was unset, so test-file classification was heuristic; the source checkout was shallow and SonarQube reported missing blame information for 734 files. The JavaScript/TypeScript analysis was memory intensive: the c7i-flex.large SonarQube host experienced OOM kills during an earlier attempt. A later analysis completed and the dashboard showed the quality gate as passed. The passed dashboard result is evidence of a successful completed analysis, while the earlier failed run documents a capacity limitation.

**Evidence:** [`../scans/sonarqube-juice-shop-findings.xlsx`](../scans/sonarqube-juice-shop-findings.xlsx) and sanitized onboarding screenshots in [`../evidence/sonarqube/`](../evidence/sonarqube/).

### DAST — Nuclei

Nuclei v3.11.1 ran on the private scanner EC2 host against `http://10.30.20.52:3000`. Before scanning, a scanner-host `curl` check returned HTTP 200. Nuclei reported one informational result:

```text
[swagger-api] [http] [info] http://10.30.20.52:3000/api-docs/swagger.json [paths="/api-docs/swagger.json"]
```

This indicates the API documentation endpoint was reachable. It is an informational exposure observation, not proof of an exploitable vulnerability. The Nuclei run used a low request rate/concurrency and disabled Interactsh callbacks. The result was copied from the scanner output into the project artifact based on the user-provided terminal output; it was not downloaded directly from the scanner host.

**Evidence:** [`../scans/nuclei/nuclei-juice-shop-results.txt`](../scans/nuclei/nuclei-juice-shop-results.txt), [`../scans/nuclei/README.md`](../scans/nuclei/README.md).

Trivy and OWASP ZAP were discussed during planning but no completed scan result for either is retained here; they are not counted as completed tests.

## IAM assessment

### Implemented or observed

- EC2 instance roles were used for SSM agent access; no static AWS credentials were put in the application container or image.
- The Terraform IAM module defines EC2-trusted roles and an SSM agent policy with `ssm:UpdateInstanceInformation` and `ssmmessages` channel actions. The policy uses `Resource = "*"`, which is typical for these agent channel operations but should be kept limited to the required action set.
- Terraform attached the same `target` instance profile to both the Juice Shop and scanner EC2 instances. This avoided granting the app administrator permissions, but it means the two workloads shared one role boundary.
- During the session, the target role was denied `iam:ListAttachedRolePolicies` and `ec2:DescribeInstanceTypes`. This is consistent with those actions not being granted to that instance role; it is not a complete proof of all effective permissions.
- An S3 source-archive read policy was created during the lab workflow according to the user's Terraform apply output. The checked-in mirror of the IAM module does not contain that policy, so deployed IAM and the final repository source are not fully reconciled. Treat this as a source/state documentation gap.

### Assessment and improvements

The role is narrower than an administrator role, but best practice is to separate app and scanner roles. The Juice Shop application should have only the SSM agent permissions it needs and no source-download or scan privileges. The scanner should receive only the narrowly scoped source artifact access needed for scans, if any. Remove unused `admin` role/profile resources and S3 transfer permissions from a future Project 2B-specific module if they are not used. Review the final policy documents and role attachments from a saved Terraform plan/state or AWS IAM snapshot before claiming a complete IAM audit; those deployed records were not retained in this artifact set.

## Network and exposure assessment

### Intended topology and verified observations

- Dedicated VPC with a public subnet for NAT and private subnets for app and scanner; both EC2 instances had no public IP in the Terraform configuration.
- No inbound SSH rule was defined for app or scanner. SSM was the management path, and an SSM port-forward was used for local access to the app/SonarQube service.
- The app security group ingress rule allowed TCP 3000 only from the scanner security group. The scanner security group had no inbound application access requirement.
- The scanner reached the Juice Shop private IP on TCP 3000 and received HTTP 200, demonstrating the intended scanner-to-app route was functioning.
- App and scanner outbound HTTPS was configured for packages, image pulls, and SSM. Private subnet default routes traversed a NAT Gateway. The NAT Gateway, EIP, EC2, and data transfer were cost-bearing; no WAF was deployed because the app had no public HTTP ingress.
- Terraform destroy reported 39 resources destroyed. A subsequent read-only EC2 query returned no matching running/stopped project instances. This confirms no matching EC2 instances remained, but does not independently verify every non-EC2 resource.

### Configuration review findings / caveats

1. **Egress requires final-state validation.** The Terraform source creates security groups and separate egress-rule resources but does not explicitly declare empty inline ingress/egress lists in the `aws_security_group` resources. Review provider behavior and the applied plan/state to ensure AWS's default allow-all egress was actually removed. The deployment evidence does not preserve a `describe-security-groups` snapshot, so do not claim outbound destinations were conclusively restricted.
2. **Shared role boundary.** Scanner and app shared a target instance profile. Split roles before reusing this pattern beyond the disposable lab.
3. **No runtime host-hardening evidence.** The project reused IAM/network module code from Project 1B, but the evidence set does not show a Project 2B Ansible hardening playbook successfully applied and verified. Do not claim host hardening was completed. The app host required manual Docker installation after cloud-init failed to find a `docker.io` candidate; package metadata was refreshed and Docker was installed manually.
4. **Container settings diverged from IaC.** The bootstrap template specifies `--read-only` and a tmpfs at `/juice-shop/data`; startup failed because Juice Shop writes additional files during initialization. The successful manual run omitted `--read-only` and used an anonymous Docker volume for `/juice-shop/data`, while retaining dropped capabilities, `no-new-privileges`, PID and memory limits, and no host data bind mount. Update the bootstrap template before the next deployment and verify container filesystem needs rather than assuming the current template is what ran.
5. **Single AZ and NAT trade-off.** The lab is intentionally single-AZ and has no high availability. NAT simplifies outbound downloads and SSM connectivity but carries hourly and data-processing charges. Destroying the stack was appropriate after the scans; retain the billable-resource cleanup check for future runs.

## Conclusion and next improvements

The exercise demonstrated private AWS deployment, SSM administration, constrained scanner-to-app access, and practical SCA/SAST/DAST evidence collection. The most important follow-ups are to reconcile deployed IAM with version-controlled Terraform, split app/scanner roles, verify restrictive egress, correct the Docker bootstrap to match the successful runtime configuration, and add a tested Project 2B Ansible baseline. For the application findings, use the raw Dependency-Check HTML and SonarQube issue detail to validate high-impact items, then document triage rather than attempting to make the deliberately vulnerable Juice Shop pass all checks.

## Limitations

This report is assembled from the Terraform source and outputs, terminal outputs, screenshots, and scan artifacts available in the project workspace and conversation. A retained AWS configuration snapshot, full effective IAM policy evaluation, complete SonarQube issue export, and complete Nuclei JSONL output were not available. Conclusions that depend on those missing items are marked as caveats rather than verified facts. Secrets and SonarQube tokens are intentionally excluded.
