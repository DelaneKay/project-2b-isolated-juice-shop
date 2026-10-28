# Project 2B — Step-by-step lab walkthrough

This is a chronological reconstruction of the commands and outcomes recorded in the project chat. It separates commands run on the **WSL workstation** from commands run inside **EC2 Systems Manager (SSM) sessions**. The EC2 prompt was usually `ssm-user@ip-...`; that shell does not contain the WSL project checkout. Exit an SSM session before using local project paths.

This is a lab record, not a claim that every security control was production-ready. Where a command below is cleaned up for repeatability, the text says so. Identifiers and IP addresses are historical and change on redeployment. Never paste an AWS password, access key, NVD key, or Sonar token into this document or command history. The Sonar token appeared in the chat during troubleshooting; revoke/rotate it before any further use. The published screenshots have been redacted.

## Lab at a glance

- **Target:** OWASP Juice Shop `bkimminich/juice-shop:v17.1.1` on private EC2, Docker, port 3000.
- **Operator path:** AWS CLI short-lived login and Systems Manager; no SSH ingress and no public IP on the app or scanner.
- **Scan path:** private scanner EC2 to app EC2 on TCP 3000. SCA used OWASP Dependency-Check; SAST used SonarQube Community Build; DAST used Nuclei.
- **Not used:** AWS WAF (no public HTTP entry point), Trivy, OWASP ZAP, and a completed Project 2B Ansible hardening run.
- **Cleanup:** Terraform reported 39 resources destroyed; a follow-up EC2 query showed no project instances. A complete post-destroy inventory of every AWS resource type was not retained.

The VPC, IAM, and storage modules were reused and adapted from Project 1B, then included in this repository under `modules/`. Project 2B has its own Terraform root for app/scanner instances and security groups. The module source is therefore available to someone cloning this repository; it does not depend on a sibling Project 1B checkout.

## 1. Start in the WSL project checkout

The lab was continued in the existing WSL checkout rather than rebuilding the directory tree. The project was under:

```text
/home/devsecops/projects/project-2b-isolated-juice-shop
```

In a **WSL terminal**, check the project and move to the Terraform root:

```bash
cd ~/projects/project-2b-isolated-juice-shop
find . -maxdepth 3 -type f | sort
cd terraform
```

The inventory showed the Terraform root, the `modules/` tree, `docs/`, `ansible/`, and `scans/`. When commands were accidentally run inside an EC2 SSM shell, `cd ~/projects/project-2b-isolated-juice-shop` failed because that WSL path exists only on the workstation. Return to the WSL prompt for repository, Git, and local report work.

## 2. Log in to AWS and review Terraform

The lab used the home-lab CLI profile `mds-devsecops-lab` and region `us-east-1`. The AWS CLI login session was short-lived. When Terraform returned `ExpiredToken` or said the login session expired, authenticate again before retrying; do not change credentials in Terraform.

In **WSL**, from `terraform/`:

```bash
aws login --profile mds-devsecops-lab
aws sts get-caller-identity --profile mds-devsecops-lab
terraform init
terraform fmt -recursive
terraform validate
terraform plan
```

The chat records an early Terraform module error: `modules/storage/main.tf` referred to `data.aws_caller_identity.current`, but that data source had only been declared in the root module. Terraform modules do not inherit root data resources. The storage module needed its own caller-identity data declaration. An S3 VPC endpoint policy was also updated to permit the Docker image layer download path. An early `terraform fmt -recursive` was accidentally run from the project root and treated a file path as a directory; run it from the Terraform directory as above.

Review the plan before applying. It showed **40 resources to add** on a successful plan. Pay attention to NAT Gateway/EIP cost, EC2 instance types, IAM policies, S3 bucket, and network rules. The lab was later recreated, so output IDs differ across runs.

```bash
terraform apply
terraform output
```

A successful apply returned the Juice Shop instance ID/private IP, scanner instance ID, VPC ID, and an SSM port-forward command. Do not copy old IDs into a new run; use `terraform output` and the current EC2/SSM status instead.

## 3. Verify the private network and open SSM sessions

The design had a private app host and private scanner host. The app security group allowed TCP 3000 from the scanner security group; the scanner had no inbound rule. No SSH rule or public IP was intended. SSM was the administration path. Both hosts used the target instance profile for SSM agent channels, and the host role did not have permission to inspect IAM policies or EC2 instance types; attempts to call `iam:ListAttachedRolePolicies` and `ec2:DescribeInstanceTypes` were denied as expected for that role.

From **WSL**, start an interactive shell on a host using its current ID from Terraform output:

```bash
aws ssm start-session --target <CURRENT_INSTANCE_ID> --region us-east-1 --profile mds-devsecops-lab
```

Use one WSL terminal/session for the app host and another for the scanner when you need both. Commands prefixed with `sudo` in the next sections run in the relevant **EC2 SSM shell**, not WSL. SSM sessions sometimes expired after inactivity; reconnect with the command above. Port-forwarding also failed at times with a Session Manager plugin handshake timeout even though the plugin was installed; check `session-manager-plugin --version`, verify the instance is Online, and retry with a different local port. Do not infer an app failure from a port-forward handshake failure.

The generated Juice Shop port-forward command used `AWS-StartPortForwardingSession` and remote port 3000. SonarQube used remote port 9000. Keep the forwarding command running in one WSL terminal; use the browser or `curl` from another. The service itself was checked on the EC2 host with `curl http://127.0.0.1:9000/api/system/status`; its status moved from `STARTING` to `UP`.

## 4. Install Docker and bring Juice Shop up

### 4.1 Diagnose the failed bootstrap

Cloud-init initially failed in `scripts_user`; `docker` was not installed and `sudo docker` returned `command not found`. On the **Juice Shop EC2 SSM shell**, the diagnostic commands used were:

```bash
sudo cloud-init status --long
sudo tail -n 100 /var/log/cloud-init-output.log
sudo apt-cache policy docker.io
```

The bootstrap log said `Package 'docker.io' has no installation candidate`. The Ubuntu package source was later available, and manual installation succeeded. The host reported Docker `29.1.3-0ubuntu3~24.04.2`.

```bash
sudo apt-get update
sudo apt-get install -y docker.io
sudo systemctl enable --now docker
sudo systemctl is-active docker
sudo docker --version
```

The successful checks returned `active` and Docker version `29.1.3`. An attempt to install the Ubuntu `awscli` package on EC2 also failed because there was no installation candidate; AWS CLI was installed in WSL instead. The target EC2 role initially received S3 `403 AccessDenied`, so the WSL identity with bucket permissions performed the successful S3 transfer.

### 4.2 Pull the pinned application image

On the **app EC2 SSM shell**:

```bash
sudo docker pull bkimminich/juice-shop:v17.1.1
sudo docker ps -a
```

The pull succeeded (image digest recorded in the terminal) but `docker ps -a` was empty until a container was started.

### 4.3 Correct the read-only filesystem failure

The first manual container attempt included `--read-only` and a tmpfs for `/juice-shop/data`. Juice Shop restarted with `ENOENT` while copying its chatbot training file. Adding an anonymous volume at `/juice-shop/data` fixed that missing-path error, but the read-only root filesystem then failed when Juice Shop initialized `.well-known/csaf/provider-metadata.json` and other generated files (`EROFS`). These were application startup writes, not evidence of an image download failure.

The working command removed `--read-only`, used an anonymous data volume, and retained the other runtime restrictions. In the **app EC2 SSM shell**:

```bash
sudo docker rm -f juice-shop 2>/dev/null || true
sudo docker run -d \
  --name juice-shop \
  --restart unless-stopped \
  --publish 3000:3000 \
  --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  --volume /juice-shop/data \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --pids-limit 256 \
  --memory 768m \
  bkimminich/juice-shop:v17.1.1
sudo docker ps -a --filter name=juice-shop
sudo docker logs juice-shop --tail 30
```

The container reached `Up` and published port 3000 on the host. Although Docker displayed `0.0.0.0:3000`, the instance had no public IP and the AWS security group restricted app ingress to the scanner security group. The actual cloud-init template in the repository still includes `--read-only`; it must be reconciled with the working command before a future Terraform deployment. The manual run also used an anonymous volume, so application state was ephemeral.

From the **scanner EC2 SSM shell**, the app first returned `Connection refused` while Juice Shop was not running. After the container was fixed, the same private endpoint check returned HTTP 200:

```bash
curl -sS -o /dev/null -w 'HTTP %{http_code}\n' --max-time 10 http://10.30.20.52:3000/
```

`10.30.20.52` is the address from the later successful run only. On a new deployment, get the current private IP with `terraform output` or EC2 metadata rather than copying this one.

## 5. Prepare the Juice Shop source for scans

The source repository was cloned in **WSL** into `scans/juice-shop` at tag `v17.1.1`. Git printed a detached-HEAD warning because the tag points to a commit rather than a branch; that is normal for checking out a fixed release tag.

```bash
cd ~/projects/project-2b-isolated-juice-shop
mkdir -p scans
cd scans
git clone --branch v17.1.1 --depth 1 https://github.com/juice-shop/juice-shop.git juice-shop
```

For the image-filesystem Dependency-Check scan, the pinned container image was pulled on the app/scanner host and its filesystem (including `node_modules`) was packaged and transferred to the scanner. The archive was about 93 MB. The first attempt to run `aws s3 cp` inside the SSM shell failed because `aws` was not installed there; after installing AWS CLI v2, the instance role still received `403 AccessDenied` for the transfer bucket. The archive was uploaded/downloaded from **WSL**, where the lab CLI profile had S3 access. Keep the source archive and scan artifacts in the lab bucket only as long as required.

Example transfer shape (use the current bucket name from the deployment; do not copy an old account-specific bucket name):

```bash
# WSL: set this to the exact bucket name, then upload the archive
BUCKET_NAME="replace-with-exact-lab-bucket-name"
aws s3 cp /tmp/juice-shop-v17.1.1.tar.gz "s3://${BUCKET_NAME}/juice-shop-v17.1.1.tar.gz" --region us-east-1 --profile mds-devsecops-lab

# WSL: download a generated report after it is made available through the chosen transfer path
aws s3 cp "s3://${BUCKET_NAME}/replace-with-report-object-key" scans/ --region us-east-1 --profile mds-devsecops-lab
```

The commands above show the clean WSL transfer pattern. They are not a claim that the EC2 instance role had direct S3 access; it did not. The target role's least-privilege policy was intentionally narrow, and the observed `403` was retained as evidence.

## 6. Run SCA with OWASP Dependency-Check

### 6.1 Initial failures and recovery

The Dependency-Check Docker image was pulled on the scanner. The report directory was initially empty because scans exited before report generation. Logs showed an invalid NVD API key (`NvdApiException`), followed by `No documents exist`; an empty/malformed key was also tested accidentally because the SSM shell was `/bin/sh` and `read -s` is a Bash option. Use `bash` before a Bash-specific silent prompt. A later run completed analysis and wrote the HTML report, but Dependency-Check warned that a cached web data source could not be refreshed and might omit recent vulnerabilities. The stored report is useful assessment evidence, but its NVD freshness is limited by that warning.

### 6.2 Command used for the report

The working scan used the `owasp/dependency-check:latest` image with the source mounted read-only and cache/report directories mounted persistently. The terminal paste had line-wrap artifacts; the readable command form is:

```bash
sudo mkdir -p /opt/odc-data /opt/odc-image-reports
sudo chown -R 1000:1000 /opt/odc-data /opt/odc-image-reports
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

The image tag used in the session was `latest`; pin a version or digest for a reproducible rerun. The successful output said `Analysis Complete` and `Writing HTML report to: /report/dependency-check-report.html`. The report was about 35 MB and was copied into `scans/juice-shop-v17.1.1-dependency-check-report.html`. On WSL the transfer was performed with `curl` against a temporary local HTTP endpoint/port-forward and saved with `-o` into the project; the download showed 100% received. The final local-copy command was:

```bash
curl -f http://localhost:8000/dependency-check-report.html \
  -o ~/projects/project-2b-isolated-juice-shop/scans/juice-shop-v17.1.1-dependency-check-report.html
```

The HTML is included in this repository.

The recorded summary was 17,799 dependency records, 13,484 unique dependencies, 115 vulnerable dependency records, 513 vulnerability associations, 259 distinct CVE identifiers, and no suppressions. Counts by scanner severity were 29 Critical, 48 High, 33 Medium/Moderate, and 5 Low. These are tool matches, not confirmed exploitability. The analyzer logged unsupported CVSS vectors for some npm audit results and said Sonatype OSS Index was disabled without credentials. See [`../scans/juice-shop-v17.1.1-dependency-check-summary.md`](../scans/juice-shop-v17.1.1-dependency-check-summary.md) and the full [HTML report](../scans/juice-shop-v17.1.1-dependency-check-report.html).

## 7. Run SAST with SonarQube Community Build

### 7.1 Start SonarQube and access it privately

SonarQube Community Build `26.9.0.129388` ran in Docker on a temporary scanner-sized EC2 Spot instance. The first smaller `t3.small` scanner was insufficient for the JavaScript/TypeScript scan. The kernel OOM killer terminated the Java analyzer during the 54k-line project scan. A separate temporary `c7i-flex.large` Spot instance was used for SonarQube; it was stopped/destroyed with the lab. Do not describe it as always-on capacity.

The host's resource checks were:

```bash
free -h
df -h /
nproc
```

The host had about 3.7 GiB available to the VM/container setup and no swap. SonarQube startup was checked locally on the EC2 host:

```bash
sudo docker ps -a --filter name=sonarqube
sudo docker logs --tail 80 sonarqube
curl -sS http://127.0.0.1:9000/api/system/status
```

The service reported `STARTING` before changing to `UP`; `curl -I http://127.0.0.1:9000` returned HTTP 200 once ready. The container was published on loopback (`127.0.0.1:9000->9000/tcp`), not directly to the internet. From **WSL**, SSM port forwarding was used to expose local port 19000 to remote port 9000. Some attempts to port-forward to local port 9000 or 19000 failed with a Session Manager plugin handshake timeout; checking the plugin version and retrying the session resolved access. The session command form was:

```bash
aws ssm start-session \
  --target <CURRENT_SONAR_EC2_ID> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["9000"],"localPortNumber":["19000"]}' \
  --region us-east-1 \
  --profile mds-devsecops-lab
```

Keep that command running. Browse to `http://127.0.0.1:19000` from the WSL/Windows workstation. The SonarQube local project was named **OWASP Juice Shop v17.1.1**, project key `juice-shop-2b`, and branch `master`. The account's project token was generated in the UI; it must not be written in Git, shell history, screenshots, or this walkthrough. A token appeared in earlier chat material, so revoke it and generate a fresh one before another analysis.

### 7.2 Run the scanner

The Sonar onboarding page suggested installing `@sonar/scan` globally. That was attempted in WSL but failed with `EACCES` under `/usr/lib/node_modules`; `docker` was also not installed on WSL. Scanning was moved to the EC2 host, where Docker was available, using the `sonarsource/sonar-scanner-cli:latest` image. One early scan returned HTTP 401 because the token passed to the container was not accepted. The token/API check later returned HTTP 200 and analysis submission succeeded. Do not use the raw token printed in a previous terminal or screenshot.

The exact successful full scanner invocation was not preserved as a clean text transcript. This is a **safe repeat pattern**, not a claim to reproduce the secret-bearing command verbatim. On the SonarQube EC2 host, use Bash for the silent prompt, ensure the source path exists, and run the scanner container with host networking so `127.0.0.1:9000` reaches the host SonarQube service:

```bash
bash
sudo test -f /opt/juice-shop-src/package.json && echo "Juice Shop source is ready"
read -rsp 'SonarQube project token: ' SONAR_TOKEN
printf '\n'
export SONAR_TOKEN
sudo -E docker run --rm --network host \
  -e SONAR_HOST_URL=http://127.0.0.1:9000 \
  -e SONAR_TOKEN \
  -v /opt/juice-shop-src:/usr/src \
  -w /usr/src \
  sonarsource/sonar-scanner-cli:latest \
  -Dsonar.projectKey=juice-shop-2b
unset SONAR_TOKEN
```

The actual scan first OOMed on the smaller host and returned 401 on a token attempt. After using the temporary Spot host and an accepted token, the analysis completed. The dashboard showed Quality Gate **Passed**; Overall Code showed 127 security issues (rating E), 132 reliability issues (rating D), and 605 maintainability issues (rating A). The project showed about 54k lines and version 17.1.1. The Sonar analysis warned that Python version and `sonar.tests` were not configured, the checkout was shallow, and blame was missing for 734 files. The workbook in `../scans/sonarqube-juice-shop-findings.xlsx` is a curated record of the issues pasted into chat, not a complete SonarQube export. Screenshots committed to `evidence/sonarqube/` have the token covered.

## 8. Run DAST with Nuclei

Nuclei v3.11.1 was installed on the **scanner EC2 SSM shell**. The first release URL used returned HTTP 404, so the versioned Linux AMD64 release archive was downloaded and unpacked. Nuclei printed version `v3.11.1`, installed its templates, and reported no template updates at that time.

The scanner initially had no `nuclei` command until the binary was installed. The first curl to `http://10.30.20.52:3000/` returned `Connection refused` because Juice Shop was not listening then. After the app container was started, the scanner received HTTP 200. The scan was then run against the lab's private app address; result output was written under `/tmp` on the scanner host. The terminal output we retained was one informational match:

```text
[swagger-api] [http] [info] http://10.30.20.52:3000/api-docs/swagger.json [paths="/api-docs/swagger.json"]
```

The result file could not be saved directly from the EC2 shell into the WSL checkout: `cd ~/projects/...` failed there and `mkdir scans/...` hit a permissions error. It was retrieved by printing the scanner's `/tmp/nuclei-juice-shop-results.txt` over an SSM interactive command, then saving it in WSL:

```bash
# WSL, not the SSM shell
cd ~/projects/project-2b-isolated-juice-shop
mkdir -p scans/nuclei
cat > scans/nuclei/nuclei-juice-shop-results.txt
# paste the single Nuclei output line, then press Ctrl-D
```

The checked-in Nuclei result is a one-line transcription of the terminal output, not the scanner's full JSONL output. Nuclei produced only an informational Swagger API documentation finding. Trivy and OWASP ZAP were not run.

## 9. Review IAM, network, and controls

The assessment is in [`security-assessment.md`](security-assessment.md), with the topology in [`architecture.md`](architecture.md). The review found:

- Private app/scanner subnets, no public IPs, no inbound SSH, SSM used for operator access.
- App ingress limited to TCP 3000 from the scanner security group; the scanner made the DAST request over that path.
- IMDSv2 required and encrypted gp3 root volumes in Terraform.
- Both EC2 hosts used the same target instance profile. The observed role could not call `iam:ListAttachedRolePolicies` or `ec2:DescribeInstanceTypes`; this is evidence of least privilege for those actions, not a full IAM audit.
- Egress was configured for HTTPS and scanner-to-app TCP 3000 in Terraform source. A final deployed SG snapshot was not retained, so effective egress was not independently confirmed.
- The app's successful manual Docker run did not use a read-only filesystem; the checked-in bootstrap template still needs correction before redeployment.
- A successful Project 2B Ansible baseline run was not evidenced. Project 1B's SFTP-specific playbook was not suitable to apply unchanged.
- WAF was intentionally omitted because no public HTTP endpoint was deployed. That means this lab did not test WAF behavior.

## 10. Destroy the AWS lab and check for billable leftovers

The user stopped resources overnight to avoid costs. Later the infrastructure was recreated for the remaining scans, then torn down. An initial `terraform destroy` removed 39 resources but failed to delete the S3 transfer bucket because it was not empty. A bucket-removal attempt failed when the short-lived AWS login session expired. After reauthenticating, the bucket contents were removed and `terraform destroy` completed with **39 resources destroyed**. A follow-up EC2 query showed no project instances. The conversation did not retain a complete inventory of all resource types after teardown.

In **WSL**, first confirm you're in the correct Terraform root and authenticated profile. Then inspect the destroy plan and enter `yes` only if it targets this lab:

```bash
cd ~/projects/project-2b-isolated-juice-shop/terraform
aws login --profile mds-devsecops-lab
terraform destroy
```

If the lab bucket is non-empty, set its exact name and verify the account, region, and contents before removing objects. The bucket removal is destructive to objects in that bucket:

```bash
BUCKET_NAME="replace-with-exact-lab-bucket-name"
aws s3 ls "s3://${BUCKET_NAME}" --region us-east-1 --profile mds-devsecops-lab
aws s3 rm "s3://${BUCKET_NAME}" --recursive --region us-east-1 --profile mds-devsecops-lab
```

After Terraform exits, check the project EC2 instances and separately review NAT Gateways, Elastic IPs, S3 buckets, EBS snapshots, and VPCs in the same account/region. Terraform's 39-resource message plus the no-instances query is the evidence retained here; it is not proof that every possible billable resource type was checked.

## 11. Results and remaining work

**Completed:** reused/adapted Terraform modules, private EC2 deployment, Docker-hosted Juice Shop, SCA with Dependency-Check and saved HTML report, SonarQube SAST and curated issue workbook, Nuclei DAST result, IAM/network assessment, and Terraform teardown.

**Not completed or not retained:** complete SonarQube issue export, full Nuclei JSONL output, Trivy image scan, OWASP ZAP scan, successfully applied Project 2B Ansible hardening, final effective IAM/security-group snapshots, and complete post-destroy inventory. Before redeployment, reconcile the app cloud-init template with the successful Docker run and rotate credentials that appeared in chat.
