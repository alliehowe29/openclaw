# OpenClaw Infrastructure - Main Configuration
# AWS provider and common data sources

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # Uncomment after initial apply to enable remote state
  backend "s3" {
    bucket         = "openclaw-terraform-state-730335670792"
    key            = "openclaw/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "openclaw-terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "openclaw"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Get available AZs in the region
data "aws_availability_zones" "available" {
  state = "available"
}

# Local values for common configurations
locals {
  name_prefix = "openclaw-${var.environment}"
  account_id  = data.aws_caller_identity.current.account_id

  # Use first 2 AZs for high availability
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  common_tags = {
    Project     = "openclaw"
    Environment = var.environment
  }
}
