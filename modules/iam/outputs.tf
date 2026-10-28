output "admin_instance_profile_name" { value = aws_iam_instance_profile.admin.name }
output "target_instance_profile_name" { value = aws_iam_instance_profile.target.name }

output "admin_role_name" { value = aws_iam_role.admin.name }
