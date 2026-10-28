# Project 2B — End-to-end lab walkthrough

This walkthrough reconstructs the steps performed in the lab conversation and the project artifacts. It records actual outcomes, including failures and corrections, rather than presenting every initial attempt as successful. Do not copy any secret from terminal history or screenshots into a repository. Values such as instance IDs and private IPs below are historical evidence and will change on a new deployment.

## 1. Define the lab and its boundaries

The objective was to deploy the intentionally vulnerable OWASP Juice Shop on EC2, keep it private, and assess it with SCA, SAST, and DAST tools. The design chosen was **private EC2 + Docker + SSM**, without a public application endpoint and without AWS WAF. WAF was not needed for this deployment because the application had no public HTTP entry point; the aim was to assess IAM, security groups, host/container controls, dependencies, code, and private runtime exposure.

The Terraform network, IAM, and storage modules were adapted from Project 1B and vendored under `modules/`, so a clone of this project contains its own local module source. Project 2B defined the Juice Shop/scanner EC2 resources and workload security groups in its Terraform root. The original Project 1B modules had SFTP-specific assumptions, so they were not blindly applied to the application.

## 2. Authenticate and inspect the Terraform plan

Run these commands in **WSL**, from the project Terraform directory. Use the configured home-lab profile; never put passwords, access keys, session tokens, NVD keys, or SonarQube tokens in Terraform files or shell history.

```bash
cd ~/projects/project-2b-isolated-juice-shop/terraform
aws login --profile mds-devsecops-lab
aws sts get-caller-identity --profile mds-devsecops-lab
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out=project-2b.tfplan
```

Review the plan carefully, especially the NAT Gateway, EIP, EC2 instances, IAM roles, S3 bucket, and VPC. One initial apply/plan attempt failed because the short-lived AWS login session expired. Re-authenticate, then rerun the command. A later plan showed 40 resources to add; apply completed and output the app, scanner, VPC, and SSM-forward details. Resource identifiers changed after the lab was recreated, so obtain them from Terraform outputs rather than reusing IDs from this walkthrough.

```bash
terraform apply project-2b.tfplan
terraform output
```

The Terraform template initially had a module reference error for `data.aws_caller_identity.current` inside the storage module. The module needs to declare its own data source, because Terraform modules do not inherit data resources from the root. After correcting that and the S3 endpoint policy for Docker's image layer download, formatting/validation/planning proceeded.

## 3. Connect to the private hosts with SSM

From **WSL**, retrieve the instance IDs using Terraform outputs and start separate SSM sessions for the app and scanner. Example using the deployed IDs from the successful deployment (replace with current outputs on a new run):

```bash
aws ssm start-session --target "$(terraform output -raw juice_shop_instance_id)" --region us-east-1 --profile mds-devsecops-lab
aws ssm start-session --target "$(terraform output -raw scanner_instance_id)" --region us-east-1 --profile mds-devsecops-lab
```

The app and scanner were private EC2 instances; there was no SSH ingress. The scanner-to-app test later returned HTTP 200 on TCP 3000. SSM sessions sometimes timed out after inactivity. If a session ends, reconnect from WSL. For SonarQube access, keep a port-forward session running in a separate WSL terminal while using the local browser.

## 4. Start Juice Shop and resolve the bootstrap failure

The first app bootstrap failed because cloud-init could not find a `docker.io` installation candidate. In the **Juice Shop EC2 SSM shell**, refresh package metadata and install Docker:

```bash
sudo apt-get update
sudo apt-cache policy docker.io
sudo apt-get install -y docker.io
sudo systemctl enable --now docker
sudo docker --version
```

The EC2 source showed Docker `29.1.3-0ubuntu3~24.04.2`. The first container start used `--read-only`; Juice Shop then crashed while initializing because it writes files outside the narrowly configured writable paths. The successful manual run removed `--read-only`, kept its data in an anonymous Docker volume, and retained capability dropping, `no-new-privileges`, PID and memory limits:

```bash
sudo docker run -d \
  --name juice-shop \
  --restart unless-stopped \
  --pull always \
  --publish 3000:3000 \
  --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  --volume /juice-shop/data \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --pids-limit 256 \
  --memory 768m \
  bkimminich/juice-shop:v17.1.1
```

Verify from the app host with `sudo docker ps -a --filter name=juice-shop`. From the **scanner EC2 SSM shell**, test the private path:

```bash
curl -sS -o /dev/null -w 'HTTP %{http_code}\n' --max-time 10 http://10.30.20.52:3000/
```

The scanner returned HTTP 200 after the app container was corrected. The committed cloud-init template still needs the correction documented in the assessment report before redeployment.

## 5. Run SCA with OWASP Dependency-Check

The scanner host had Docker, and the pinned Juice Shop image was pulled. Its application filesystem, including `node_modules`, was copied into a source directory and transferred through the lab's private S3 transfer bucket. The scan ran in the Dependency-Check Docker image with read-only source input and persistent cache/report mounts. An initial attempt with an NVD API key failed with an invalid-key error; the key is intentionally omitted from this walkthrough. A later scan used the hosted NVD cache without that key and completed, although the scanner warned its cached vulnerability data might not be current.

Representative command (run in the **scanner EC2 SSM shell**, after source/cache/report directories exist):

```bash
sudo docker run --rm \
  -v /opt/juice-shop-src:/src:ro \
  -v /opt/odc-data:/usr/share/dependency-check/data \
  -v /opt/odc-image-reports:/report \
  owasp/dependency-check:latest \
  --project "OWASP Juice Shop v17.1.1" \
  --scan /src \
  --format HTML \
  --out /report
```

The HTML report was retrieved to WSL and saved as [`../scans/juice-shop-v17.1.1-dependency-check-report.html`](../scans/juice-shop-v17.1.1-dependency-check-report.html). The recorded output was 35 MB. Summary: 17,799 dependency records, 13,484 unique dependencies, 115 vulnerable dependency records, 513 vulnerability associations, 259 distinct CVE identifiers, and no suppressions. It reported 29 Critical, 48 High, 33 Medium/Moderate, and 5 Low vulnerable dependency records. These are scanner matches, not confirmed exploitability. See the [SCA summary](../scans/juice-shop-v17.1.1-dependency-check-summary.md).

During troubleshooting, the report directory was empty because a container exited before report generation; logs later showed `Invalid API Key` and `No documents exist`. The final run completed analysis and wrote the HTML report. Unsupported npm CVSS vector warnings and the disabled Sonatype OSS Index analyzer are recorded in the report summary.

## 6. Run SAST with SonarQube Community Build

SonarQube was run temporarily on a separate scanner-sized EC2 instance. The original `t3.small` scanner could not support the JavaScript/TypeScript analysis workload; logs showed the kernel OOM killer terminating Java and the scanner. The temporary SonarQube host was increased to a `c7i-flex.large` Spot instance. It was accessed privately through SSM port forwarding to local port 9000. The browser showed HTTP 200 from the locally forwarded service once startup completed.

The SonarScanner CLI was run in Docker against the Juice Shop source checkout. The project key used was `juice-shop-2b`. Do not save the generated SonarQube token in source, README, screenshots, command history, or this walkthrough. Supply it only at runtime through a protected prompt/environment variable. A 401 response means the token/project permission or token source must be checked; eventually the token validation returned HTTP 200 and the analysis completed.

The JavaScript/TypeScript analyzer later exhausted memory on an earlier attempt. After restarting the temporary SonarQube service and rerunning successfully, the SonarQube dashboard showed:

- Quality gate: **Passed**
- Overall Code: **127 Security issues, rating E**
- Overall Code: **132 Reliability issues, rating D**
- Overall Code: **605 Maintainability issues, rating A**
- Approximately 54k lines of code; project version 17.1.1

The analysis also warned that Python version and `sonar.tests` were not configured, the checkout was shallow, and blame was missing for 734 files. The workbook under `../scans/sonarqube-juice-shop-findings.xlsx` is a curated summary, not the complete SonarQube issue export. Representative issue excerpts and caveats are in [`security-assessment.md`](security-assessment.md).

## 7. Run DAST with Nuclei

Nuclei v3.11.1 was installed on the **scanner EC2 instance**. The first attempted release asset URL returned 404; the versioned Linux AMD64 release archive was used successfully. The binary checksum was verified and templates were installed/updated. The scan was scoped to the private Juice Shop URL with a low rate, limited concurrency, and no Interactsh callbacks:

```bash
nuclei -u http://10.30.20.52:3000 \
  -severity info,low,medium,high,critical \
  -rl 5 -c 5 -timeout 10 -retries 1 \
  -no-interactsh \
  -o /tmp/nuclei-juice-shop-results.txt
```

An initial scanner connectivity test returned `Connection refused` because Juice Shop was not running on the app host. After Docker was installed and the app container was started, the scanner's connectivity check returned HTTP 200. Nuclei reported one informational endpoint:

```text
[swagger-api] [http] [info] http://10.30.20.52:3000/api-docs/swagger.json [paths="/api-docs/swagger.json"]
```

The SSM session ended before copying the file directly. The one-line result was transcribed into the WSL project based on the terminal output and saved in `../scans/nuclei/`; it is not a full JSONL export. Trivy and OWASP ZAP were not run.

## 8. IAM and network review

The Terraform source and lab observations are assessed in [`security-assessment.md`](security-assessment.md). The core results were: no public app endpoint or SSH ingress; SSM was the operator path; scanner-to-app access was restricted to TCP 3000 by security-group reference; the app/scanner shared the same target EC2 instance profile; the role's observed denials included `iam:ListAttachedRolePolicies` and `ec2:DescribeInstanceTypes`; and no successful Project 2B Ansible hardening run was evidenced. No final security-group/IAM snapshot was retained, so the report does not overstate verification of all effective permissions or egress rules.

## 9. Destroy resources and verify teardown

After scans, the lab was destroyed to stop EC2/NAT-related costs. An early destroy attempt failed because the transfer bucket was not empty; the first bucket-removal attempt also hit an expired AWS session. After re-authentication and emptying the lab bucket, `terraform destroy` reported **39 resources destroyed**. A follow-up EC2 query for the project returned no instances.

In **WSL**:

```bash
cd ~/projects/project-2b-isolated-juice-shop/terraform
aws login --profile mds-devsecops-lab
terraform destroy
```

Review the proposed destroy and type `yes` only after confirming it is limited to the lab. The user observed 39 resources destroyed and no project EC2 instances on the read-only follow-up query. A complete post-destroy inventory of every AWS resource type was not retained, so the final claim is limited to Terraform's destroy result and the EC2 check. Always check for NAT Gateways, EIPs, buckets, snapshots, and other billable leftovers in the target account after future runs.

## 10. What was completed and what remains

Completed: isolated private EC2 lab deployment, Docker-hosted Juice Shop v17.1.1, SCA with Dependency-Check, SAST with SonarQube, Nuclei DAST, Terraform destroy, scan evidence collection, and IAM/network findings write-up.

Not completed or not evidenced: a retained complete SonarQube issue export, a full Nuclei JSONL artifact, Trivy image scan, OWASP ZAP scan, a successfully applied Project 2B Ansible host-hardening baseline, and a complete AWS post-destroy resource inventory. The app's manual runtime container settings also differed from the checked-in bootstrap template and should be reconciled before a repeat deployment.
