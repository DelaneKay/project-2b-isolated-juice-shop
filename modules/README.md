# Vendored Terraform modules

These modules are copied from the author's Project 1B Terraform and included here so a GitHub clone of Project 2B contains every local module source it needs. Project 2B does not reference the Project 1B directory.

| Module | Source files | Used for |
| --- | --- | --- |
| `network` | `main.tf`, `variables.tf`, `outputs.tf` | Dedicated VPC, private scanner/app subnets, NAT, routes, and S3 endpoint |
| `iam` | `main.tf`, `variables.tf`, `outputs.tf` | SSM-enabled EC2 instance roles and profiles; Project 2B uses the least-privileged target profile for both hosts |
| `storage` | `main.tf`, `variables.tf`, `outputs.tf` | Private short-lived Ansible transfer bucket required by the reused network and IAM module interfaces |

The source modules remain in Project 1B; these copies are independently vendored and can be adapted for Project 2B without changing the original lab. The Project 2B root adds app/scanner EC2 resources and app-specific security groups in `terraform/main.tf`, because Project 1B's compute and security-group modules are SFTP-oriented.
