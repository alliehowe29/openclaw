# OpenClaw Infrastructure - Output Values

# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

# ECR Outputs
output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.main.repository_url
}

output "ecr_repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.main.name
}

# ECS Outputs
output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.main.name
}

output "ecs_task_definition_arn" {
  description = "ARN of the ECS task definition"
  value       = aws_ecs_task_definition.main.arn
}

# ALB Outputs
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer (for Route 53)"
  value       = aws_lb.main.zone_id
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.main.arn
}

# CloudWatch Outputs
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.ecs.name
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

# Bastion Outputs (conditional)
output "bastion_public_ip" {
  description = "Public IP of the bastion host"
  value       = var.enable_bastion ? aws_eip.bastion[0].public_ip : null
}

output "bastion_instance_id" {
  description = "Instance ID of the bastion host"
  value       = var.enable_bastion ? aws_instance.bastion[0].id : null
}

# EC2 App Outputs (conditional)
output "ec2_app_public_ip" {
  description = "Public IP of the EC2 app server"
  value       = var.enable_ec2_app ? aws_eip.ec2_app[0].public_ip : null
}

output "ec2_app_instance_id" {
  description = "Instance ID of the EC2 app server"
  value       = var.enable_ec2_app ? aws_instance.ec2_app[0].id : null
}

output "ec2_app_ssh_command" {
  description = "SSH command to connect to the EC2 app server"
  value       = var.enable_ec2_app ? "ssh -i ~/.ssh/${var.ec2_app_key_name}.pem ec2-user@${aws_eip.ec2_app[0].public_ip}" : null
}

output "ec2_app_gateway_endpoint" {
  description = "Gateway endpoint URL for the EC2 app server (direct IP access)"
  value       = var.enable_ec2_app ? "http://${aws_eip.ec2_app[0].public_ip}:${var.container_port}" : null
}

output "ec2_app_tailscale_hostname" {
  description = "Tailscale hostname for the EC2 app server (access via your tailnet)"
  value       = var.enable_ec2_app ? "openclaw-${var.environment}" : null
}

output "ec2_app_tailscale_url" {
  description = "Tailscale Serve URL (replace <tailnet> with your tailnet name)"
  value       = var.enable_ec2_app ? "https://openclaw-${var.environment}.<tailnet>.ts.net/" : null
}

# Terraform State Outputs
output "terraform_state_bucket" {
  description = "Name of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "terraform_locks_table" {
  description = "Name of the DynamoDB table for Terraform locks"
  value       = aws_dynamodb_table.terraform_locks.name
}

# Useful Commands Output
output "useful_commands" {
  description = "Useful commands for managing the infrastructure"
  value = {
    login_to_ecr      = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.main.repository_url}"
    push_image        = "docker push ${aws_ecr_repository.main.repository_url}:latest"
    update_service    = "aws ecs update-service --cluster ${aws_ecs_cluster.main.name} --service ${aws_ecs_service.main.name} --force-new-deployment"
    view_logs         = "aws logs tail ${aws_cloudwatch_log_group.ecs.name} --follow"
    ssm_to_bastion    = var.enable_bastion ? "aws ssm start-session --target ${aws_instance.bastion[0].id}" : "bastion not enabled"
    gateway_endpoint  = "http://${aws_lb.main.dns_name}"
    ssm_to_ec2_app    = var.enable_ec2_app ? "aws ssm start-session --target ${aws_instance.ec2_app[0].id}" : "ec2 app not enabled"
    ec2_app_endpoint  = var.enable_ec2_app ? "http://${aws_eip.ec2_app[0].public_ip}:${var.container_port}" : "ec2 app not enabled"
    ec2_app_view_logs = var.enable_ec2_app ? "aws logs tail /ec2/openclaw-${var.environment} --follow" : "ec2 app not enabled"
  }
}
