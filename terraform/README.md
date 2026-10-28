# Project 2B Terraform deployment

This root provisions private EC2 hosts for Juice Shop and authorized scanning. It uses the vendored Terraform modules in the sibling `../modules/` directory, so a clone of this repository includes the module source files. Terraform state is separate from Project 1B.

## Design

- Dedicated VPC with private scanner and app subnets.
- The reused network module creates a NAT Gateway for outbound HTTPS and an S3 Gateway endpoint. The NAT Gateway is billable while it exists.
- No public instance IPs or inbound SSH rules.
- Juice Shop is reachable on TCP 3000 only from the scanner security group. SSM port forwarding from your workstation does not require an inbound app rule.
- Both EC2 hosts use the vendored target instance profile, which grants SSM agent channel permissions only.
- EC2 requires IMDSv2 and uses encrypted gp3 root storage.
- The successful manual Juice Shop container used a pinned image tag, an anonymous data volume, dropped capabilities, no-new-privileges, and PID/memory limits. It did not use a read-only root filesystem: Juice Shop startup writes files beyond the configured data directory. The cloud-init template still contains `--read-only` and must be corrected before redeployment.

Project 1B's compute module creates SFTP-specific resources, so Project 2B defines its own EC2 instances. Its security-group module has no scanner-to-app rule, so Project 2B defines the workload security groups locally.

## Before deployment

The lab was deployed, assessed, and destroyed. The user observed Terraform report 39 resources destroyed, and a follow-up query returned no project EC2 instances. Before a future redeployment, confirm the account, region, image tag, and lab window. Set a budget alert and review cost-bearing resources in the plan, especially NAT Gateway, EIP, EC2, and data transfer. Ensure the VPC CIDR does not overlap with any connected network. See [`../docs/security-assessment.md`](../docs/security-assessment.md) for results and teardown evidence limits.

From this directory:

```sh
terraform init
terraform fmt -check -recursive ..
terraform validate
terraform plan
```

Use `terraform.tfvars.example` as a starting point for a local `terraform.tfvars`; do not commit account-specific settings. Review the plan before applying.

After deployment, confirm SSM connectivity for both hosts. Use the `ssm_port_forward_command` output from your workstation, then browse to `http://localhost:3000`. From the scanner instance, scan the app's private IP on TCP 3000 for authorized DAST. The caller needs AWS permissions for Terraform and SSM; this project creates EC2 agent roles, not workstation operator permissions.

## Ansible hardening

Do not apply Project 1B's `harden-target.yml` unchanged: it requires an SFTP data-volume mount and configures a chrooted SFTP user. Build a Project 2B playbook from applicable baseline controls such as updates, AppArmor, auditd, sysctl, and host firewall. Preserve Docker and SSM connectivity, then verify scanner-to-app access after hardening.

## Scanning

- **SCA:** OWASP Dependency-Check against Juice Shop source and dependency manifests.
- **SAST:** SonarQube Community Build against the source checkout.
- **Container scan:** Trivy against the exact deployed image tag.
- **DAST:** ZAP and/or Nuclei from the private scanner host against the Juice Shop private address. Limit scans to this lab.

Juice Shop is deliberately vulnerable. Do not expose it publicly or connect it to real data.

## Cleanup

Run `terraform destroy` from this directory when the assessment is complete. Confirm the NAT Gateway, EIP, EC2 instances, S3 transfer bucket, and VPC are removed. The bucket must be empty before Terraform can delete it. Retain only sanitized reports and screenshots.

