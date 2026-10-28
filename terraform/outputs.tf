output "juice_shop_instance_id" {
  description = "Private EC2 instance ID running Juice Shop."
  value       = aws_instance.juice_shop.id
}

output "scanner_instance_id" {
  description = "Private EC2 instance ID for running authorized lab scans."
  value       = aws_instance.scanner.id
}

output "juice_shop_private_ip" {
  description = "Private app address, reachable only from the scanner security group."
  value       = aws_instance.juice_shop.private_ip
}

output "vpc_id" {
  description = "Dedicated Project 2B VPC ID."
  value       = module.network.vpc_id
}

output "ssm_port_forward_command" {
  description = "Run locally after AWS CLI and Session Manager plugin are configured."
  value       = "aws ssm start-session --target ${aws_instance.juice_shop.id} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"3000\"],\"localPortNumber\":[\"3000\"]}' --region ${var.aws_region}"
}
