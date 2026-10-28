variable "aws_region" {
  description = "AWS region for the isolated Project 2B lab."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Unique prefix for Project 2B resources and bucket."
  type        = string
  default     = "mds-juice-shop-2b"
}

variable "vpc_cidr" {
  description = "Dedicated lab VPC address range."
  type        = string
  default     = "10.30.0.0/16"
}

variable "availability_zone" {
  description = "Single AZ keeps this learning lab small."
  type        = string
  default     = "us-east-1a"
}

variable "public_subnet_cidr" {
  description = "Public subnet used only by the NAT Gateway."
  type        = string
  default     = "10.30.0.0/24"
}

variable "scanner_private_subnet_cidr" {
  description = "Private subnet for the scanner EC2 host."
  type        = string
  default     = "10.30.10.0/24"
}

variable "app_private_subnet_cidr" {
  description = "Private subnet for the Juice Shop EC2 host."
  type        = string
  default     = "10.30.20.0/24"
}

variable "app_instance_type" {
  description = "EC2 size for Juice Shop."
  type        = string
  default     = "t3.small"
}

variable "scanner_instance_type" {
  description = "EC2 size for the isolated scanner host."
  type        = string
  default     = "t3.small"
}

variable "root_volume_size_gib" {
  description = "Encrypted gp3 root volume size for each lab host."
  type        = number
  default     = 20
}

variable "juice_shop_image" {
  description = "Pinned Juice Shop container image tag; avoid floating tags for reproducible scans."
  type        = string
  default     = "bkimminich/juice-shop:v17.1.1"
}
