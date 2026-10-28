terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = "isolated-learning-lab"
    ManagedBy   = "Terraform"
  }
}

data "aws_caller_identity" "current" {}

data "aws_ssm_parameter" "ubuntu_2404_amd64" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

module "storage" {
  source = "../modules/storage"

  project_name = var.project_name
  common_tags  = local.common_tags
  aws_region   = var.aws_region
}

module "network" {
  source = "../modules/network"

  project_name                = var.project_name
  common_tags                 = local.common_tags
  aws_region                  = var.aws_region
  vpc_cidr                    = var.vpc_cidr
  availability_zone           = var.availability_zone
  public_subnet_cidr          = var.public_subnet_cidr
  admin_private_subnet_cidr   = var.scanner_private_subnet_cidr
  target_private_subnet_cidr  = var.app_private_subnet_cidr
  ansible_transfer_bucket_arn = module.storage.bucket_arn
}

module "iam" {
  source = "../modules/iam"

  project_name                = var.project_name
  common_tags                 = local.common_tags
  aws_region                  = var.aws_region
  ansible_transfer_bucket_arn = module.storage.bucket_arn
}

resource "aws_security_group" "juice_shop" {
  name        = "${var.project_name}-juice-shop-sg"
  description = "Juice Shop is reachable only from the isolated scanner; users connect through SSM port forwarding"
  vpc_id      = module.network.vpc_id

  tags = merge(local.common_tags, { Name = "${var.project_name}-juice-shop-sg" })
}

resource "aws_security_group" "scanner" {
  name        = "${var.project_name}-scanner-sg"
  description = "Private scanner host with no inbound access"
  vpc_id      = module.network.vpc_id

  tags = merge(local.common_tags, { Name = "${var.project_name}-scanner-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "juice_shop_from_scanner" {
  security_group_id            = aws_security_group.juice_shop.id
  referenced_security_group_id = aws_security_group.scanner.id
  description                  = "Juice Shop application port from the lab scanner only"
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
}

resource "aws_vpc_security_group_egress_rule" "juice_shop_https" {
  security_group_id = aws_security_group.juice_shop.id
  description       = "HTTPS for updates and container image retrieval"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "scanner_https" {
  security_group_id = aws_security_group.scanner.id
  description       = "HTTPS for updates, scanner images, and SSM"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "scanner_to_juice_shop" {
  security_group_id            = aws_security_group.scanner.id
  referenced_security_group_id = aws_security_group.juice_shop.id
  description                  = "DAST traffic to the Juice Shop application"
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
}

resource "aws_instance" "juice_shop" {
  ami                         = data.aws_ssm_parameter.ubuntu_2404_amd64.value
  instance_type               = var.app_instance_type
  subnet_id                   = module.network.target_subnet_id
  vpc_security_group_ids      = [aws_security_group.juice_shop.id]
  iam_instance_profile        = module.iam.target_instance_profile_name
  associate_public_ip_address = false
  user_data = templatefile("${path.module}/templates/juice-shop.sh.tftpl", {
    image = var.juice_shop_image
  })

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = var.root_volume_size_gib
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(local.common_tags, { Name = "${var.project_name}-juice-shop", Role = "application" })
}

resource "aws_instance" "scanner" {
  ami                         = data.aws_ssm_parameter.ubuntu_2404_amd64.value
  instance_type               = var.scanner_instance_type
  subnet_id                   = module.network.admin_subnet_id
  vpc_security_group_ids      = [aws_security_group.scanner.id]
  iam_instance_profile        = module.iam.target_instance_profile_name
  associate_public_ip_address = false
  user_data                   = file("${path.module}/templates/scanner-host.sh")

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = var.root_volume_size_gib
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(local.common_tags, { Name = "${var.project_name}-scanner", Role = "scanner" })
}




