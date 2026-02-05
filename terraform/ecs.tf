# OpenClaw Infrastructure - ECS Cluster and Service

# Generate random gateway token
resource "random_password" "gateway_token" {
  length  = 32
  special = false
}

# Store gateway token in Secrets Manager
resource "aws_secretsmanager_secret" "gateway_token" {
  name = "openclaw/${var.environment}/gateway-token"

  tags = {
    Name = "${local.name_prefix}-gateway-token"
  }
}

resource "aws_secretsmanager_secret_version" "gateway_token" {
  secret_id     = aws_secretsmanager_secret.gateway_token.id
  secret_string = random_password.gateway_token.result
}

# Slack App Token (set value manually in AWS Console after apply)
resource "aws_secretsmanager_secret" "slack_app_token" {
  name = "openclaw/${var.environment}/slack-app-token"

  tags = {
    Name = "${local.name_prefix}-slack-app-token"
  }
}

# Slack Bot Token (set value manually in AWS Console after apply)
resource "aws_secretsmanager_secret" "slack_bot_token" {
  name = "openclaw/${var.environment}/slack-bot-token"

  tags = {
    Name = "${local.name_prefix}-slack-bot-token"
  }
}

# Anthropic API Key (set value manually in AWS Console after apply)
resource "aws_secretsmanager_secret" "anthropic_api_key" {
  name = "openclaw/${var.environment}/anthropic-api-key"

  tags = {
    Name = "${local.name_prefix}-anthropic-api-key"
  }
}

# Browserbase API Key (set value manually in AWS Console after apply)
resource "aws_secretsmanager_secret" "browserbase_api_key" {
  name = "openclaw/${var.environment}/browserbase-api-key"

  tags = {
    Name = "${local.name_prefix}-browserbase-api-key"
  }
}

# Browserbase Project ID (set value manually in AWS Console after apply)
resource "aws_secretsmanager_secret" "browserbase_project_id" {
  name = "openclaw/${var.environment}/browserbase-project-id"

  tags = {
    Name = "${local.name_prefix}-browserbase-project-id"
  }
}

# Secret Key (set value manually in AWS Console after apply)
resource "aws_secretsmanager_secret" "secret_key" {
  name = "openclaw/${var.environment}/secret-key"

  tags = {
    Name = "${local.name_prefix}-secret-key"
  }
}

# OpenAI API Key (set value manually in AWS Console after apply)
resource "aws_secretsmanager_secret" "openai_api_key" {
  name = "openclaw/${var.environment}/openai-api-key"

  tags = {
    Name = "${local.name_prefix}-openai-api-key"
  }
}

# OpenAI Organization ID (optional, set value manually in AWS Console after apply)
resource "aws_secretsmanager_secret" "openai_org_id" {
  name = "openclaw/${var.environment}/openai-org-id"

  tags = {
    Name = "${local.name_prefix}-openai-org-id"
  }
}

# Tailscale Auth Key (set value manually in AWS Console after apply)
resource "aws_secretsmanager_secret" "tailscale_auth_key" {
  name = "openclaw/${var.environment}/tailscale-auth-key"

  tags = {
    Name = "${local.name_prefix}-tailscale-auth-key"
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${local.name_prefix}-cluster"
  }
}

# ECS Cluster Capacity Providers
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# ECS Task Execution Role
resource "aws_iam_role" "ecs_task_execution" {
  name = "${local.name_prefix}-ecs-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-ecs-task-execution"
  }
}

# Attach AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional policy for SSM Parameter access
resource "aws_iam_role_policy" "ecs_task_execution_ssm" {
  name = "${local.name_prefix}-ecs-task-execution-ssm"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameters",
          "ssm:GetParameter",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${local.account_id}:parameter/openclaw/*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${local.account_id}:secret:openclaw/*"
      }
    ]
  })
}

# ECS Task Role (for the application itself)
resource "aws_iam_role" "ecs_task" {
  name = "${local.name_prefix}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-ecs-task"
  }
}

# Task role policy for application permissions
resource "aws_iam_role_policy" "ecs_task" {
  name = "${local.name_prefix}-ecs-task-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameters",
          "ssm:GetParameter",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${local.account_id}:parameter/openclaw/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.ecs.arn}:*"
      }
    ]
  })
}

# ECS Task Definition
resource "aws_ecs_task_definition" "main" {
  family                   = "${local.name_prefix}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name  = "openclaw-gateway"
      image = "${aws_ecr_repository.main.repository_url}:latest"

      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]

      command = [
        "node",
        "dist/index.js",
        "gateway",
        "--bind",
        "lan",
        "--port",
        tostring(var.container_port)
      ]

      environment = [
        {
          name  = "NODE_ENV"
          value = "production"
        },
        {
          name  = "PORT"
          value = tostring(var.container_port)
        },
        {
          name  = "OPENCLAW_GATEWAY_MODE"
          value = "local"
        }
      ]

      secrets = [
        {
          name      = "OPENCLAW_GATEWAY_TOKEN"
          valueFrom = aws_secretsmanager_secret.gateway_token.arn
        },
        {
          name      = "SLACK_APP_TOKEN"
          valueFrom = aws_secretsmanager_secret.slack_app_token.arn
        },
        {
          name      = "SLACK_BOT_TOKEN"
          valueFrom = aws_secretsmanager_secret.slack_bot_token.arn
        },
        {
          name      = "ANTHROPIC_API_KEY"
          valueFrom = aws_secretsmanager_secret.anthropic_api_key.arn
        },
        {
          name      = "BROWSERBASE_API_KEY"
          valueFrom = aws_secretsmanager_secret.browserbase_api_key.arn
        },
        {
          name      = "BROWSERBASE_PROJECT_ID"
          valueFrom = aws_secretsmanager_secret.browserbase_project_id.arn
        },
        {
          name      = "SECRET_KEY"
          valueFrom = aws_secretsmanager_secret.secret_key.arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "gateway"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      essential = true
    }
  ])

  tags = {
    Name = "${local.name_prefix}-task"
  }
}

# ECS Service
resource "aws_ecs_service" "main" {
  name            = "${local.name_prefix}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.ecs_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = "openclaw-gateway"
    container_port   = var.container_port
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Allow external changes to desired_count (e.g., from auto scaling)
  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_lb_listener.http]

  tags = {
    Name = "${local.name_prefix}-service"
  }
}

# Auto Scaling Target
resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = var.autoscaling_max_capacity
  min_capacity       = var.autoscaling_min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.main.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Auto Scaling Policy - CPU
resource "aws_appautoscaling_policy" "ecs_cpu" {
  name               = "${local.name_prefix}-cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.autoscaling_cpu_target
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
