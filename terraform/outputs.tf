# 1. Public ALB Endpoint
output "alb_dns_name" {
  description = "Public URL of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

# 2. EC2 Instance Public IPs (for Ansible inventory)
output "blue_instance_ip" {
  description = "Public IPv4 of Blue instance"
  value       = aws_instance.blue.public_ip
}

output "green_instance_ip" {
  description = "Public IPv4 of Green instance"
  value       = aws_instance.green.public_ip
}

# 3. Target Group ARNs (for Jenkins Blue-Green switching)
output "blue_target_group_arn" {
  description = "ARN of Blue Target Group"
  value       = aws_lb_target_group.blue.arn
}

output "green_target_group_arn" {
  description = "ARN of Green Target Group"
  value       = aws_lb_target_group.green.arn
}

output "alb_listener_arn" {
  description = "ARN of ALB HTTP Listener"
  value       = aws_lb_listener.http.arn
}

# 4. ECR Repositories
output "ecr_backend_url" {
  description = "ECR Repository URL for Backend"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_frontend_url" {
  description = "ECR Repository URL for Frontend"
  value       = aws_ecr_repository.frontend.repository_url
}
