# OpenClaw Infrastructure - Input Variables

variable "aws_region" {
  description = "AWS region for OpenClaw infrastructure"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name (e.g., prod, staging, dev)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "Environment must be one of: prod, staging, dev."
  }
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for the OpenClaw VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

# ECS Configuration
variable "ecs_task_cpu" {
  description = "CPU units for the OpenClaw ECS task (1024 = 1 vCPU)"
  type        = number
  default     = 512
}

variable "ecs_task_memory" {
  description = "Memory (MiB) for the OpenClaw ECS task"
  type        = number
  default     = 1024
}

variable "ecs_desired_count" {
  description = "Desired number of OpenClaw ECS tasks"
  type        = number
  default     = 1
}

variable "container_port" {
  description = "Port the OpenClaw gateway listens on"
  type        = number
  default     = 18789
}

# EC2 Bastion Configuration
variable "enable_bastion" {
  description = "Whether to create an EC2 bastion host for debugging"
  type        = bool
  default     = false
}

variable "bastion_instance_type" {
  description = "Instance type for the bastion host"
  type        = string
  default     = "t3.micro"
}

variable "bastion_key_name" {
  description = "SSH key pair name for bastion access"
  type        = string
  default     = ""
}

# Domain Configuration
variable "domain_name" {
  description = "Domain name for the OpenClaw gateway (optional)"
  type        = string
  default     = ""
}

variable "certificate_arn" {
  description = "ARN of ACM certificate for HTTPS (optional)"
  type        = string
  default     = ""
}

# Monitoring Configuration
variable "alarm_email" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
}

# Auto Scaling Configuration
variable "autoscaling_min_capacity" {
  description = "Minimum number of ECS tasks"
  type        = number
  default     = 1
}

variable "autoscaling_max_capacity" {
  description = "Maximum number of ECS tasks"
  type        = number
  default     = 4
}

variable "autoscaling_cpu_target" {
  description = "Target CPU utilization percentage for auto scaling"
  type        = number
  default     = 70
}

# EC2 App Configuration (Alternative to ECS)
variable "enable_ec2_app" {
  description = "Whether to create an EC2 instance for OpenClaw gateway (alternative to ECS)"
  type        = bool
  default     = false
}

variable "ec2_app_instance_type" {
  description = "Instance type for the EC2 app server"
  type        = string
  default     = "t3.medium"  # Needs 4GB+ RAM for TypeScript compilation
}

variable "ec2_app_key_name" {
  description = "SSH key pair name for EC2 app access"
  type        = string
  default     = ""
}
