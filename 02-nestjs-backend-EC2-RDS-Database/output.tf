output "aws_elb_public_dns" {
    value = aws_elb.web.dns_name
}

output "rds_hostname" {
  value       = aws_db_instance.default.address
  sensitive   = true
}

output "rds_port" {
  value       = aws_db_instance.default.port
  sensitive   = true
}

output "rds_username" {
  value       = aws_db_instance.default.username
  sensitive   = true
}