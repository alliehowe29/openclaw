# OpenClaw Infrastructure - EC2 App Server (Alternative to ECS Fargate)
# This provides a simpler deployment option with direct EC2 access

# IAM Role for EC2 App
resource "aws_iam_role" "ec2_app" {
  count = var.enable_ec2_app ? 1 : 0

  name = "${local.name_prefix}-ec2-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-ec2-app-role"
  }
}

# Attach SSM policy for Session Manager access
resource "aws_iam_role_policy_attachment" "ec2_app_ssm" {
  count = var.enable_ec2_app ? 1 : 0

  role       = aws_iam_role.ec2_app[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Policy for SecretsManager and CloudWatch access
resource "aws_iam_role_policy" "ec2_app" {
  count = var.enable_ec2_app ? 1 : 0

  name = "${local.name_prefix}-ec2-app-policy"
  role = aws_iam_role.ec2_app[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${local.account_id}:secret:openclaw/*"
      },
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
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.ec2_app[0].arn}:*"
      }
    ]
  })
}

# IAM Instance Profile for EC2 App
resource "aws_iam_instance_profile" "ec2_app" {
  count = var.enable_ec2_app ? 1 : 0

  name = "${local.name_prefix}-ec2-app-profile"
  role = aws_iam_role.ec2_app[0].name
}

# Security Group for EC2 App
resource "aws_security_group" "ec2_app" {
  count = var.enable_ec2_app ? 1 : 0

  name        = "${local.name_prefix}-ec2-app-sg"
  description = "Security group for OpenClaw EC2 app server"
  vpc_id      = aws_vpc.main.id

  # SSH access
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Restrict this in production
  }

  # HTTP access
  ingress {
    description = "HTTP access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS access
  ingress {
    description = "HTTPS access"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Gateway port access
  ingress {
    description = "OpenClaw gateway port"
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Tailscale UDP port for direct connections
  ingress {
    description = "Tailscale UDP"
    from_port   = 41641
    to_port     = 41641
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-ec2-app-sg"
  }
}

# CloudWatch Log Group for EC2 App
resource "aws_cloudwatch_log_group" "ec2_app" {
  count = var.enable_ec2_app ? 1 : 0

  name              = "/ec2/openclaw-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "/ec2/openclaw-${var.environment}"
  }
}

# EC2 App Instance
resource "aws_instance" "ec2_app" {
  count = var.enable_ec2_app ? 1 : 0

  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.ec2_app_instance_type
  key_name               = var.ec2_app_key_name != "" ? var.ec2_app_key_name : null
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.ec2_app[0].id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_app[0].name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true
    delete_on_termination = true
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -ex

    # Update system
    dnf update -y

    # Install dependencies (curl-minimal is pre-installed on AL2023, don't install curl)
    dnf install -y docker git jq

    # Start and enable Docker
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ec2-user

    # Install Node.js 22
    curl -fsSL https://rpm.nodesource.com/setup_22.x | bash -
    dnf install -y nodejs

    # Install pnpm
    npm install -g pnpm

    # Install OpenClaw CLI globally
    npm install -g openclaw

    # Install Tailscale
    curl -fsSL https://tailscale.com/install.sh | sh

    # Create OpenClaw directories
    mkdir -p /home/ec2-user/.openclaw
    mkdir -p /home/ec2-user/openclaw
    chown -R ec2-user:ec2-user /home/ec2-user/.openclaw
    chown -R ec2-user:ec2-user /home/ec2-user/openclaw

    # Create environment file directory
    mkdir -p /etc/openclaw

    # Create Tailscale auth service (runs before gateway to authenticate)
    cat > /etc/systemd/system/tailscale-auth.service <<'TSAUTH'
    [Unit]
    Description=Tailscale Authentication
    After=tailscaled.service network-online.target
    Wants=tailscaled.service network-online.target
    Before=openclaw-gateway.service

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=/usr/local/bin/tailscale-auth.sh
    StandardOutput=journal
    StandardError=journal

    [Install]
    WantedBy=multi-user.target
    TSAUTH

    # Create Tailscale auth script
    cat > /usr/local/bin/tailscale-auth.sh <<'TSAUTHSCRIPT'
    #!/bin/bash
    set -e

    REGION="${var.aws_region}"
    ENV="${var.environment}"

    # Get Tailscale auth key from Secrets Manager
    TS_AUTH_KEY=$(aws secretsmanager get-secret-value \
      --region "$REGION" \
      --secret-id "openclaw/$ENV/tailscale-auth-key" \
      --query SecretString \
      --output text 2>/dev/null || echo "")

    if [ -z "$TS_AUTH_KEY" ]; then
      echo "No Tailscale auth key found, skipping Tailscale authentication"
      exit 0
    fi

    # Check if already authenticated
    if ! tailscale status --json 2>/dev/null | jq -e '.Self.Online' >/dev/null 2>&1; then
      echo "Authenticating with Tailscale..."
      tailscale up --authkey="$TS_AUTH_KEY" --hostname="openclaw-${var.environment}"
    else
      echo "Tailscale already authenticated"
    fi

    tailscale status
    TSAUTHSCRIPT

    chmod +x /usr/local/bin/tailscale-auth.sh

    # Create systemd service for OpenClaw gateway with Tailscale serve mode
    # OpenClaw handles tailscale serve configuration natively via --tailscale serve
    cat > /etc/systemd/system/openclaw-gateway.service <<'SYSTEMD'
    [Unit]
    Description=OpenClaw Gateway
    After=network.target tailscaled.service tailscale-auth.service
    Wants=tailscaled.service
    Requires=tailscale-auth.service

    [Service]
    Type=simple
    User=ec2-user
    WorkingDirectory=/home/ec2-user/openclaw
    ExecStartPre=+/usr/local/bin/openclaw-load-secrets.sh
    ExecStart=/usr/bin/node dist/index.js gateway --bind loopback --port ${var.container_port} --tailscale serve
    Restart=always
    RestartSec=10
    EnvironmentFile=/etc/openclaw/env
    StandardOutput=journal
    StandardError=journal

    [Install]
    WantedBy=multi-user.target
    SYSTEMD

    # Create secrets loader script
    cat > /usr/local/bin/openclaw-load-secrets.sh <<'SECRETS'
    #!/bin/bash
    set -e

    REGION="${var.aws_region}"
    ENV="${var.environment}"

    # Function to get secret value
    get_secret() {
      aws secretsmanager get-secret-value \
        --region "$REGION" \
        --secret-id "openclaw/$ENV/$1" \
        --query SecretString \
        --output text 2>/dev/null || echo ""
    }

    # Load secrets into environment file
    cat > /etc/openclaw/env <<ENVFILE
    NODE_ENV=production
    PORT=${var.container_port}
    OPENCLAW_GATEWAY_MODE=local
    OPENCLAW_MODEL=gpt-5.2
    OPENCLAW_GATEWAY_TOKEN=$(get_secret gateway-token)
    SLACK_APP_TOKEN=$(get_secret slack-app-token)
    SLACK_BOT_TOKEN=$(get_secret slack-bot-token)
    ANTHROPIC_API_KEY=$(get_secret anthropic-api-key)
    OPENAI_API_KEY=$(get_secret openai-api-key)
    OPENAI_ORG_ID=$(get_secret openai-org-id)
    BROWSERBASE_API_KEY=$(get_secret browserbase-api-key)
    BROWSERBASE_PROJECT_ID=$(get_secret browserbase-project-id)
    SECRET_KEY=$(get_secret secret-key)
    ENVFILE

    chmod 600 /etc/openclaw/env
    SECRETS

    chmod +x /usr/local/bin/openclaw-load-secrets.sh

    # Enable and start services
    systemctl daemon-reload
    systemctl enable tailscaled
    systemctl start tailscaled
    systemctl enable tailscale-auth
    systemctl start tailscale-auth  # Run Tailscale auth now
    systemctl enable openclaw-gateway

    # Install CloudWatch agent for log shipping
    dnf install -y amazon-cloudwatch-agent

    # Configure CloudWatch agent
    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWAGENT'
    {
      "logs": {
        "logs_collected": {
          "files": {
            "collect_list": [
              {
                "file_path": "/var/log/messages",
                "log_group_name": "/ec2/openclaw-${var.environment}",
                "log_stream_name": "{instance_id}/messages"
              }
            ]
          }
        },
        "log_stream_name": "{instance_id}"
      }
    }
    CWAGENT

    # Start CloudWatch agent
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config \
      -m ec2 \
      -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
      -s

    echo "OpenClaw EC2 app setup complete" > /tmp/setup-complete
  EOF
  )

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name = "${local.name_prefix}-ec2-app"
  }
}

# Elastic IP for EC2 App (for consistent public IP)
resource "aws_eip" "ec2_app" {
  count = var.enable_ec2_app ? 1 : 0

  instance = aws_instance.ec2_app[0].id
  domain   = "vpc"

  tags = {
    Name = "${local.name_prefix}-ec2-app-eip"
  }
}
