# Project 2B — Step-by-step lab walkthrough

I built this walkthrough from the start of our project chat through teardown. I kept the command sequence chronological and separated my **WSL workstation** commands from the commands I ran inside **EC2 Systems Manager (SSM)**. The EC2 prompt was usually `ssm-user@ip-...`; it could not see my WSL project checkout, so I exited the SSM session before using local project paths.

I wrote down what actually happened, including failed attempts, rather than presenting the lab as production-ready. When I cleaned up a command or reconstructed it because the terminal paste was incomplete, I say so. Instance IDs and IP addresses below are historical and change on redeployment. I have not included passwords, AWS keys, the NVD key, or Sonar tokens. A Sonar token appeared in the chat during troubleshooting, so I recommend revoking it and generating a new one before another analysis. I redacted the published screenshots.

## Lab at a glance

- **Target:** OWASP Juice Shop `bkimminich/juice-shop:v17.1.1` on private EC2, Docker, port 3000.
- **Operator path:** AWS CLI short-lived login and Systems Manager; no SSH ingress and no public IP on the app or scanner.
- **Scan path:** private scanner EC2 to app EC2 on TCP 3000. SCA used OWASP Dependency-Check; SAST used SonarQube Community Build; DAST used Nuclei.
- **Not used:** AWS WAF (no public HTTP entry point), Trivy, OWASP ZAP, and a completed Project 2B Ansible hardening run.
- **Cleanup:** Terraform reported 39 resources destroyed; a follow-up EC2 query showed no project instances. A complete post-destroy inventory of every AWS resource type was not retained.

I reused and adapted the VPC, IAM, and storage modules from Project 1B and included their source under `modules/`. I connected them to a separate Project 2B Terraform root for the Juice Shop and scanner hosts and their security groups. Someone cloning this repository can see the module files; the lab does not depend on a sibling Project 1B checkout.

### How I checked command coverage

I checked each distinct command family in the chat: AWS login and Terraform, SSM shell and port forwarding, Docker installation and container startup, image/source transfer, Dependency-Check, SonarQube, Nuclei, and teardown. I consolidated repeated retries into the relevant troubleshooting sections. I did not reproduce malformed terminal pastes as runnable code, and I mark command reconstructions where the original full line was not captured. A few one-off account recovery and UI clicks are described without publishing reusable password-reset or token values.

## 1. Start in the WSL project checkout

I continued in my existing WSL checkout instead of recreating the project directories. The checkout was:

```text
/home/devsecops/projects/project-2b-isolated-juice-shop
```

In **WSL**, I checked the files and moved into the Terraform root:

```bash
# WSL workstation
cd ~/projects/project-2b-isolated-juice-shop
find . -maxdepth 3 -type f | sort
cd terraform
```

The inventory showed my Terraform root, `modules/`, `docs/`, `ansible/`, and `scans/`. I once ran `cd ~/projects/project-2b-isolated-juice-shop` inside an EC2 SSM shell; it failed because that path exists only in WSL. I returned to the WSL prompt whenever I needed the repository, Git, or a local report.

## 2. Log in to AWS and review Terraform

I used the home-lab CLI profile `mds-devsecops-lab` in `us-east-1`. The AWS CLI session was short-lived. When Terraform returned `ExpiredToken` or said the login session had expired, I authenticated again before retrying; I did not put credentials in Terraform.

In **WSL**, from `terraform/`:

```bash
# WSL workstation — from the Terraform directory
aws login --profile mds-devsecops-lab
aws sts get-caller-identity --profile mds-devsecops-lab
terraform init
terraform fmt -recursive
terraform validate
terraform plan
```

Before that login, I used an authorized `root-recovery` profile once to reset the IAM user's console password. The script prompted twice without displaying the password, wrote a short-lived mode-restricted JSON file, called IAM, and removed the file. I include the sanitized command here because it was a distinct setup step; it is account-specific and only works if that profile has permission to update the user's login profile:

```bash
# WSL workstation — temporary root-recovery profile, before normal lab login
(
  set -e
  umask 077
  login_input="$(mktemp)"
  trap 'rm -f "$login_input"' EXIT

  python3 - "$login_input" <<'PY'
import getpass
import json
import sys

password = getpass.getpass("New password for mds-devsecops-lab: ")
confirmation = getpass.getpass("Enter it again: ")

if not password or password != confirmation:
    raise SystemExit("Passwords are empty or do not match. Nothing changed.")

with open(sys.argv[1], "w") as file:
    json.dump({
        "UserName": "mds-devsecops-lab",
        "Password": password,
        "PasswordResetRequired": False
    }, file)
PY

  aws iam update-login-profile \
    --cli-input-json "file://$login_input" \
    --profile root-recovery \
    --no-cli-auto-prompt
)
```

I then authenticated with the short-lived CLI login shown above. This password reset is not part of Terraform and does not create AWS resources.

I first hit a Terraform module error: `modules/storage/main.tf` referred to `data.aws_caller_identity.current`, but I had declared that data source only in the root. Child modules do not inherit root data resources, so I declared it in the storage module. I also updated the S3 VPC endpoint policy to allow the Docker image-layer download path. I initially ran `terraform fmt -recursive` from the project root and got a path error; running it from `terraform/` worked.

Review the plan before applying. It showed **40 resources to add** on a successful plan. Pay attention to NAT Gateway/EIP cost, EC2 instance types, IAM policies, S3 bucket, and network rules. The lab was later recreated, so output IDs differ across runs.

```bash
# WSL workstation — from the Terraform directory
terraform apply
terraform output
```

A successful apply returned the Juice Shop instance ID and private IP, scanner instance ID, VPC ID, and an SSM port-forward command. I used `terraform output` and the current EC2/SSM status rather than carrying old IDs into the recreated deployment.

## 3. Verify the private network and open SSM sessions

I deployed a private app host and private scanner host. The app security group allowed TCP 3000 from the scanner security group; the scanner had no inbound rule. I did not add SSH ingress or public IPs. I used SSM to administer both hosts. They shared the target instance profile for SSM agent channels. From the host role, attempts to inspect attached IAM policies and EC2 instance types were denied; those denials showed the role did not have those read permissions, but they were not a complete IAM audit.

From **WSL**, I checked that the hosts were managed and online, then opened an interactive shell using the current ID from Terraform output:

```bash
# WSL workstation
aws ssm describe-instance-information \
  --region us-east-1 \
  --profile mds-devsecops-lab \
  --query 'InstanceInformationList[].{Instance:InstanceId,Ping:PingStatus}' \
  --output table
```

I opened a host session with:

```bash
# WSL workstation — replace the placeholder with the current app or scanner instance ID
aws ssm start-session --target <CURRENT_INSTANCE_ID> --region us-east-1 --profile mds-devsecops-lab
```

I used separate WSL terminals when I needed sessions to both hosts. Commands prefixed with `sudo` in the next sections ran in the relevant **EC2 SSM shell**, not WSL. SSM sessions expired after inactivity, so I reconnected with the command above. Port forwarding also returned Session Manager plugin handshake timeouts even though the plugin was installed. I checked `session-manager-plugin --version`, confirmed the instance was Online, and retried; a handshake failure did not mean the application itself was down.

The Juice Shop forward used remote port 3000. I kept it running in one WSL terminal and opened `http://127.0.0.1:3000` locally. For SonarQube, I forwarded remote port 9000 to local port 19000 and used the browser on `http://127.0.0.1:19000`. On the SonarQube EC2 host, I checked `curl -sS http://127.0.0.1:9000/api/system/status`; its status moved from `STARTING` to `UP`.

## 4. Install Docker and bring Juice Shop up

### 4.1 Diagnose the failed bootstrap

My first cloud-init run failed in `scripts_user`; Docker was not installed, and `sudo docker` returned `command not found`. In the **Juice Shop EC2 SSM shell**, I checked the cloud-init and package state with:

```bash
# Juice Shop EC2 — SSM shell
sudo cloud-init status --long
sudo tail -n 100 /var/log/cloud-init-output.log
sudo apt-cache policy docker.io
```

The bootstrap log said `Package 'docker.io' has no installation candidate`. I changed the Ubuntu package source URLs from HTTP to HTTPS in the startup template and retried; Docker still needed a manual install. This was the source edit I used:

```bash
# Juice Shop EC2 — bootstrap script runs as root during cloud-init
for source_file in /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources; do
  if [ -f "$source_file" ]; then
    sed -i 's|http://|https://|g' "$source_file"
  fi
done
```

Manual installation succeeded, and the host reported Docker `29.1.3-0ubuntu3~24.04.2`.

```bash
# Juice Shop EC2 — SSM shell
sudo apt-get update
sudo apt-get install -y docker.io
sudo systemctl enable --now docker
sudo systemctl is-active docker
sudo docker --version
```

The successful checks returned `active` and Docker version `29.1.3`. I also tried `sudo apt-get install -y awscli` on EC2, but Ubuntu had no installation candidate. I then installed AWS CLI v2 from its official archive on the host:

```bash
# Juice Shop EC2 — SSM shell
cd /tmp
curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip
unzip -q awscliv2.zip
sudo ./aws/install
aws --version
```

The target EC2 role still received S3 `403 AccessDenied`, so I performed the successful S3 transfer from WSL using the lab profile, which had bucket access.

### 4.2 Pull the pinned application image

On the **app EC2 SSM shell**:

```bash
# App EC2 — SSM shell
sudo docker pull bkimminich/juice-shop:v17.1.1
sudo docker ps -a
```

The pull succeeded (image digest recorded in the terminal) but `docker ps -a` was empty until a container was started.

### 4.3 Correct the read-only filesystem failure

My first manual container attempt included `--read-only` and a tmpfs for `/juice-shop/data`. Juice Shop restarted with `ENOENT` while copying its chatbot training file. I added an anonymous volume at `/juice-shop/data`, which fixed that missing-path error; the read-only root filesystem then failed when Juice Shop initialized `.well-known/csaf/provider-metadata.json` and other generated files (`EROFS`). Those were startup writes, not an image download problem.

The manual command that finally started Juice Shop removed `--read-only`, used an anonymous data volume, and retained the other runtime restrictions. In the **app EC2 SSM shell**, I ran:

```bash
# App EC2 — SSM shell
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

The container reached `Up` and published port 3000 on the host. Docker displayed `0.0.0.0:3000`, but the instance had no public IP and the AWS security group allowed app ingress only from the scanner security group. My manual run used an anonymous volume, so application state was ephemeral. I later edited the startup template in WSL to remove `--read-only` and tried to correct the data mount, but the copy of the Terraform template included in this repository still has `--read-only` and the tmpfs data mount. I need to reconcile that file with the working manual command before redeploying; the manual success does not prove that the checked-in bootstrap will succeed.

From the **scanner EC2 SSM shell**, the app first returned `Connection refused` while Juice Shop was not running. After the container was fixed, the same private endpoint check returned HTTP 200:

```bash
# Scanner EC2 — SSM shell
curl -sS -o /dev/null -w 'HTTP %{http_code}\n' --max-time 10 http://10.30.20.52:3000/
```

`10.30.20.52` is the address from the later successful run only. On a new deployment, get the current private IP with `terraform output` or EC2 metadata rather than copying this one.

## 5. Prepare the Juice Shop source for scans

I cloned the Juice Shop source in **WSL** into `scans/juice-shop` at tag `v17.1.1`. Git printed a detached-HEAD warning because that tag points to a commit rather than a branch; that is expected when I check out a fixed release tag.

```bash
# WSL workstation
cd ~/projects/project-2b-isolated-juice-shop
mkdir -p scans
cd scans
git clone --branch v17.1.1 --depth 1 https://github.com/juice-shop/juice-shop.git juice-shop
```

For the image-filesystem Dependency-Check scan, I copied the pinned image's application tree, including `node_modules`, onto the EC2 host and packaged it for transfer to the scanner. The archive was about 93 MB. I first tried `aws s3 cp` inside SSM; AWS CLI was missing. After installing AWS CLI v2, the instance role still received `403 AccessDenied` for the transfer bucket. I completed the transfer from **WSL**, where my lab CLI profile had bucket access. The chat did not preserve the full `docker cp`/archive command line, so I have recorded the operation and outcome instead of inventing an exact command. I kept the archive and scan artifacts in the lab bucket only as long as needed.

Example transfer shape (use the current bucket name from the deployment; do not copy an old account-specific bucket name):

```bash
# WSL workstation — set the current bucket name, then upload the archive
# WSL: set this to the exact bucket name, then upload the archive
BUCKET_NAME="replace-with-exact-lab-bucket-name"
aws s3 cp /tmp/juice-shop-v17.1.1.tar.gz "s3://${BUCKET_NAME}/juice-shop-v17.1.1.tar.gz" --region us-east-1 --profile mds-devsecops-lab

# WSL: download a generated report after it is made available through the chosen transfer path
aws s3 cp "s3://${BUCKET_NAME}/replace-with-report-object-key" scans/ --region us-east-1 --profile mds-devsecops-lab
```

The commands above show the clean WSL transfer pattern. They are not a claim that the EC2 instance role had direct S3 access; it did not. The target role's least-privilege policy was intentionally narrow, and the observed `403` was retained as evidence.

## 6. Run SCA with OWASP Dependency-Check

### 6.1 Initial failures and recovery

I pulled the Dependency-Check image on the scanner. My report directory was initially empty because the scans exited before writing a report. The logs showed an invalid NVD API key (`NvdApiException`) and then `No documents exist`. I accidentally tried to use `read -s` from the SSM shell's `/bin/sh`; that option is Bash-specific. When I needed a hidden prompt, I switched to Bash first:

```bash
# Scanner EC2 — SSM shell; enter Bash before using the hidden prompt
bash
read -rsp 'NVD API key: ' NVD_API_KEY
printf '\n'
```

I never put the key in this walkthrough. A later run completed and wrote the HTML report, but Dependency-Check warned that a cached web data source could not be refreshed and might omit recent vulnerabilities. I treat the report as useful assessment evidence with that freshness limitation.

### 6.2 Command used for the report

I used `owasp/dependency-check:latest` with the source mounted read-only and cache/report directories mounted persistently. The image pull and readable form of the completed one-shot scan were:

```bash
# Scanner EC2 — SSM shell
sudo docker pull owasp/dependency-check:latest
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

I used the `latest` image tag; for a reproducible rerun, I should pin a version or digest. The successful output said `Analysis Complete` and `Writing HTML report to: /report/dependency-check-report.html`. The final report was about 35 MB and I saved it as `scans/juice-shop-v17.1.1-dependency-check-report.html`. In WSL I used `curl` against the temporary local HTTP endpoint/port forward; the download reached 100%. The exact command that opened the port-8000 forwarding/listener was not preserved in the chat. The local copy command I did record was:

```bash
# WSL workstation — retrieve the report through the temporary local port-8000 forward
curl -f http://localhost:8000/dependency-check-report.html \
  -o ~/projects/project-2b-isolated-juice-shop/scans/juice-shop-v17.1.1-dependency-check-report.html
```

The HTML is included in this repository.

The recorded summary was 17,799 dependency records, 13,484 unique dependencies, 115 vulnerable dependency records, 513 vulnerability associations, 259 distinct CVE identifiers, and no suppressions. Counts by scanner severity were 29 Critical, 48 High, 33 Medium/Moderate, and 5 Low. These are tool matches, not confirmed exploitability. The analyzer logged unsupported CVSS vectors for some npm audit results and said Sonatype OSS Index was disabled without credentials. See [`../scans/juice-shop-v17.1.1-dependency-check-summary.md`](../scans/juice-shop-v17.1.1-dependency-check-summary.md) and the full [HTML report](../scans/juice-shop-v17.1.1-dependency-check-report.html).

## 7. Run SAST with SonarQube Community Build

### 7.1 Start SonarQube and access it privately

I ran SonarQube Community Build `26.9.0.129388` in Docker on a temporary scanner-sized EC2 Spot instance. My initial smaller `t3.small` scanner could not handle the JavaScript/TypeScript analysis: the kernel OOM killer terminated the Java analyzer during the roughly 54k-line scan. I switched to a separate temporary `c7i-flex.large` Spot instance for SonarQube and stopped/destroyed it with the lab. It was temporary capacity, not an always-on service.

On that host, I checked available memory, disk, and CPU count with:

```bash
# SonarQube EC2 Spot host — SSM shell
free -h
df -h /
nproc
```

The host had about 3.7 GiB of memory and no swap. My earlier `t3.small` scan host was killed by the OOM killer. AWS rejected an on-demand `c7i-flex.large` modification with `FreeTierRestrictionError`, so I chose a separate Spot host. The target role could not run `ec2:DescribeInstanceTypes`; from my WSL CLI profile, I corrected the JMESPath number quoting and queried free-tier-eligible types with at least 4 GiB:

```bash
# WSL workstation — AWS CLI profile
aws ec2 describe-instance-types \
  --region us-east-1 \
  --filters "Name=free-tier-eligible,Values=true" \
  --query 'InstanceTypes[?MemoryInfo.SizeInMiB>=`4096`].[InstanceType,MemoryInfo.SizeInMiB]' \
  --output table
```

The query listed `c7i-flex.large` (4096 MiB) and `m7i-flex.large` (8192 MiB). I pulled the SonarQube image:

```bash
# SonarQube EC2 Spot host — SSM shell
sudo docker pull sonarqube:26.9.0.129388-community
```

Then I checked startup locally on the EC2 host:

```bash
# SonarQube EC2 Spot host — SSM shell
sudo docker ps -a --filter name=sonarqube
sudo docker logs --tail 80 sonarqube
curl -sS http://127.0.0.1:9000/api/system/status
```

The service reported `STARTING` before changing to `UP`; `curl -I http://127.0.0.1:9000` returned HTTP 200 once ready. Docker showed the port bound to loopback (`127.0.0.1:9000->9000/tcp`), not the public internet. From **WSL**, I forwarded local port 19000 to remote port 9000. Some attempts failed with a Session Manager plugin handshake timeout, so I checked `session-manager-plugin --version` and retried. The working command form was:

```bash
# WSL workstation — leave this port-forward session running
aws ssm start-session \
  --target <CURRENT_SONAR_EC2_ID> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["9000"],"localPortNumber":["19000"]}' \
  --region us-east-1 \
  --profile mds-devsecops-lab
```

I kept that command running, then opened `http://127.0.0.1:19000` from my workstation. In SonarQube, I created **OWASP Juice Shop v17.1.1** with project key `juice-shop-2b` and main branch `master`. I generated a project token in the UI. A token appeared in earlier chat material, so I should revoke it and create a new one before another analysis; no token belongs in Git, shell history, screenshots, or this walkthrough.

### 7.2 Run the scanner

Sonar's onboarding page suggested a global install. I tried `npm install -g @sonar/scan` in WSL, but it failed with `EACCES` under `/usr/lib/node_modules`. I also ran `sudo docker --version` there and got `docker: command not found`. I moved the scan to the EC2 host, where Docker was available, and used the `sonarsource/sonar-scanner-cli:latest` image. One attempt returned HTTP 401 because the token was not accepted. After I entered a token at the hidden prompt, the API check returned HTTP 200 and the analysis submitted. I have not copied any token from the chat into this guide.

I did not preserve the exact successful full scanner invocation as a clean text transcript. The command below is my **safe repeat pattern**, not a verbatim copy of the secret-bearing attempt. On the SonarQube EC2 host, I used Bash for the hidden prompt, checked the source path, and ran the scanner with host networking so `127.0.0.1:9000` reached the SonarQube service:

```bash
# SonarQube EC2 Spot host — SSM shell; run from Bash
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

My first scan OOMed on the smaller host and another returned 401. After I used the temporary Spot host and an accepted token, the analysis completed. The dashboard showed Quality Gate **Passed**; Overall Code showed 127 security issues (rating E), 132 reliability issues (rating D), and 605 maintainability issues (rating A). The project showed about 54k lines and version 17.1.1. Sonar warned that I had not configured the Python version or `sonar.tests`, that my checkout was shallow, and that blame was missing for 734 files. The workbook in `../scans/sonarqube-juice-shop-findings.xlsx` is a curated record of the issues pasted into chat, not a complete SonarQube export. I covered the token in the screenshots under `evidence/sonarqube/`.

## 8. Run DAST with Nuclei

I installed Nuclei v3.11.1 in the **scanner EC2 SSM shell**. My first release URL returned HTTP 404. I then downloaded the versioned Linux AMD64 archive and unpacked it; Nuclei printed `v3.11.1`, installed its templates, and reported no template updates at the time. This is the successful command pattern:

```bash
# Scanner EC2 — SSM shell
cd /tmp
curl -fL https://github.com/projectdiscovery/nuclei/releases/download/v3.11.1/nuclei_3.11.1_linux_amd64.zip \
  -o nuclei_3.11.1_linux_amd64.zip
unzip nuclei_3.11.1_linux_amd64.zip
sudo install -m 0755 nuclei /usr/local/bin/nuclei
nuclei -version
nuclei -update-templates
```

Before installing Nuclei, I got `nuclei: command not found`. My first `curl -v --max-time 10 http://10.30.20.52:3000/` from the scanner returned `Connection refused` because Juice Shop was not listening. After I started the app container, the endpoint returned HTTP 200. I ran the DAST scan against the private app address and saved its text output under `/tmp` on the scanner. The exact scan command was not included in the transcript, so this is a **reconstructed command pattern** matching the saved result filename:

```bash
# Scanner EC2 — SSM shell; reconstructed Nuclei scan command
nuclei -u http://10.30.20.52:3000 \
  -o /tmp/nuclei-juice-shop-results.txt
```

The terminal output I retained was one informational match:

```text
[swagger-api] [http] [info] http://10.30.20.52:3000/api-docs/swagger.json [paths="/api-docs/swagger.json"]
```

I could not save the result directly from the EC2 shell into my WSL checkout: `cd ~/projects/...` failed there and `mkdir scans/...` hit a permissions error. I printed the scanner's `/tmp/nuclei-juice-shop-results.txt` through an SSM interactive command, then saved it in WSL. The SSM command shape was:

```bash
# WSL workstation — run the SSM command to print the scanner saved result
aws ssm start-session \
  --target <CURRENT_SCANNER_INSTANCE_ID> \
  --region us-east-1 \
  --profile mds-devsecops-lab \
  --document-name AWS-StartInteractiveCommand \
  --parameters 'command=["sudo cat /tmp/nuclei-juice-shop-results.txt"]'
```

Back in WSL, I saved the line with:

```bash
# WSL workstation — not the SSM shell
# WSL, not the SSM shell
cd ~/projects/project-2b-isolated-juice-shop
mkdir -p scans/nuclei
cat > scans/nuclei/nuclei-juice-shop-results.txt
# paste the single Nuclei output line, then press Ctrl-D
```

The checked-in Nuclei result is a one-line transcription of the terminal output, not the scanner's full JSONL output. Nuclei produced only an informational Swagger API documentation finding. Trivy and OWASP ZAP were not run.

## 9. Review IAM, network, and controls

I recorded the assessment in [`security-assessment.md`](security-assessment.md) and the topology in [`architecture.md`](architecture.md). My review found:

- Private app/scanner subnets, no public IPs, no inbound SSH, SSM used for operator access.
- App ingress limited to TCP 3000 from the scanner security group; the scanner made the DAST request over that path.
- IMDSv2 required and encrypted gp3 root volumes in Terraform.
- Both EC2 hosts used the same target instance profile. The observed role could not call `iam:ListAttachedRolePolicies` or `ec2:DescribeInstanceTypes`; this is evidence of least privilege for those actions, not a full IAM audit.
- Egress was configured for HTTPS and scanner-to-app TCP 3000 in Terraform source. A final deployed SG snapshot was not retained, so effective egress was not independently confirmed.
- The app's successful manual Docker run did not use a read-only filesystem; the checked-in bootstrap template still needs correction before redeployment.
- A successful Project 2B Ansible baseline run was not evidenced. Project 1B's SFTP-specific playbook was not suitable to apply unchanged.
- WAF was intentionally omitted because no public HTTP endpoint was deployed. That means this lab did not test WAF behavior.

## 10. Destroy the AWS lab and check for billable leftovers

I stopped the resources overnight to avoid costs, recreated the infrastructure for the remaining scans, and destroyed it when the lab was complete. My first `terraform destroy` removed 39 resources but could not delete the S3 transfer bucket because it still contained objects. My first bucket cleanup attempt failed when the short-lived AWS session expired. After I logged in again, removed the bucket objects, and reran `terraform destroy`, Terraform reported **39 resources destroyed**. A follow-up EC2 query showed no project instances. I did not retain a full post-destroy inventory for every AWS resource type.

In **WSL**, I returned to the Terraform root, logged in again, and reran destroy. I checked the plan and confirmed it targeted this lab before answering `yes`:

```bash
# WSL workstation — from the Terraform directory
cd ~/projects/project-2b-isolated-juice-shop/terraform
aws login --profile mds-devsecops-lab
terraform destroy
```

When Terraform reported the bucket was non-empty, I set its exact name and checked the contents before deleting them. Removing these objects is destructive:

```bash
# WSL workstation — use the exact lab bucket name
BUCKET_NAME="replace-with-exact-lab-bucket-name"
aws s3 ls "s3://${BUCKET_NAME}" --region us-east-1 --profile mds-devsecops-lab
aws s3 rm "s3://${BUCKET_NAME}" --recursive --region us-east-1 --profile mds-devsecops-lab
```

After Terraform exited, I checked for project EC2 instances. I should separately review NAT Gateways, Elastic IPs, S3 buckets, EBS snapshots, and VPCs in the same account and region. The evidence I retained is Terraform's 39-resource message and the no-instances query; I cannot claim that I verified every possible billable resource type.

## 11. Results and remaining work

**I completed:** reused/adapted Terraform modules, the private EC2 deployment, Docker-hosted Juice Shop, SCA with a saved Dependency-Check HTML report, SonarQube SAST and a curated issue workbook, a Nuclei DAST run, IAM/network assessment, and Terraform teardown.

**I did not complete or retain:** a complete SonarQube issue export, full Nuclei JSONL output, Trivy image scan, OWASP ZAP scan, a successful Project 2B Ansible hardening run, final effective IAM/security-group snapshots, or a complete post-destroy inventory. Before I redeploy, I need to reconcile the checked-in app cloud-init template with the successful Docker run and rotate credentials that appeared in chat.

### Command lines I could not recover exactly

I included every distinct command family that appears in the chat and consolidated retries that repeated the same step. A few commands appeared only as wrapped or truncated terminal output, so I have not presented guesses as exact history: the full `docker cp` and archive creation line for staging the app image tree; the `docker run` line that launched the SonarQube server; the setup command for the temporary local port-8000 report transfer; and the exact Nuclei invocation (shown above as a reconstruction). I included the IAM password-reset script in sanitized form, with an interactive prompt and no password value. I left all API keys and tokens out of the walkthrough. The remaining commands are shown in the relevant sections, with the shell location identified.
