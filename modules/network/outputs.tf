output "vpc_id" { value = aws_vpc.lab.id }
output "admin_subnet_id" { value = aws_subnet.admin_private.id }
output "target_subnet_id" { value = aws_subnet.target_private.id }
