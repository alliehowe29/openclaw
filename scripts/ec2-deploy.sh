#!/usr/bin/env bash
set -euo pipefail

# EC2 Deploy Script
# Deploys code updates to the OpenClaw EC2 instance.
# Can be run locally to deploy to the remote EC2 instance.

# Configuration (can override via env vars)
AWS_REGION="${AWS_REGION:-us-west-2}"
ENVIRONMENT="${ENVIRONMENT:-prod}"
EC2_USER="${EC2_USER:-ec2-user}"
SSH_KEY="${SSH_KEY:-}"
BRANCH="${BRANCH:-main}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Get EC2 instance IP from Terraform output or AWS
get_ec2_ip() {
  # Try Terraform output first
  if command -v terraform &> /dev/null && [[ -d "terraform" ]]; then
    IP=$(cd terraform && terraform output -raw ec2_app_public_ip 2>/dev/null || echo "")
    if [[ -n "$IP" && "$IP" != "null" ]]; then
      echo "$IP"
      return
    fi
  fi

  # Fall back to AWS CLI - find instance by tag
  IP=$(aws ec2 describe-instances \
    --region "${AWS_REGION}" \
    --filters "Name=tag:Name,Values=openclaw-${ENVIRONMENT}-ec2-app" \
              "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text 2>/dev/null || echo "")

  if [[ -n "$IP" && "$IP" != "None" ]]; then
    echo "$IP"
    return
  fi

  echo ""
}

# Build SSH command
build_ssh_cmd() {
  local ip="$1"
  local cmd="ssh"

  if [[ -n "$SSH_KEY" ]]; then
    cmd="$cmd -i $SSH_KEY"
  fi

  cmd="$cmd -o StrictHostKeyChecking=accept-new ${EC2_USER}@${ip}"
  echo "$cmd"
}

# Main deployment function
deploy() {
  local ip="$1"

  echo_info "Deploying to EC2 instance at ${ip}..."

  local ssh_cmd
  ssh_cmd=$(build_ssh_cmd "$ip")

  # Run deployment commands on EC2
  $ssh_cmd << 'DEPLOY_SCRIPT'
set -e

cd /home/ec2-user/openclaw

echo "Pulling latest changes..."
git fetch origin
git checkout ${BRANCH:-main}
git pull origin ${BRANCH:-main}

echo "Installing dependencies..."
npm install --omit=dev

echo "Building project..."
npm run build

echo "Reloading secrets..."
sudo /usr/local/bin/openclaw-load-secrets.sh

echo "Restarting OpenClaw gateway..."
sudo systemctl restart openclaw-gateway

echo "Waiting for service to start..."
sleep 5

# Health check
PORT=$(grep "^PORT=" /etc/openclaw/env | cut -d= -f2)
if curl -sf "http://localhost:${PORT}/health" > /dev/null 2>&1; then
  echo "Health check passed!"
else
  echo "Warning: Health check failed"
  journalctl -u openclaw-gateway -n 20 --no-pager
  exit 1
fi
DEPLOY_SCRIPT
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --ip)
      EC2_IP="$2"
      shift 2
      ;;
    --key)
      SSH_KEY="$2"
      shift 2
      ;;
    --branch)
      BRANCH="$2"
      shift 2
      ;;
    --region)
      AWS_REGION="$2"
      shift 2
      ;;
    --environment)
      ENVIRONMENT="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 [options]"
      echo ""
      echo "Options:"
      echo "  --ip IP           EC2 instance IP address (auto-detected if not provided)"
      echo "  --key PATH        Path to SSH private key"
      echo "  --branch BRANCH   Git branch to deploy (default: main)"
      echo "  --region REGION   AWS region (default: us-west-2)"
      echo "  --environment ENV Environment name (default: prod)"
      echo "  --help            Show this help message"
      exit 0
      ;;
    *)
      echo_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

echo "=== OpenClaw EC2 Deploy ==="
echo "Region: ${AWS_REGION}"
echo "Environment: ${ENVIRONMENT}"
echo "Branch: ${BRANCH}"

# Get EC2 IP if not provided
if [[ -z "${EC2_IP:-}" ]]; then
  echo_info "Detecting EC2 instance IP..."
  EC2_IP=$(get_ec2_ip)
fi

if [[ -z "$EC2_IP" ]]; then
  echo_error "Could not determine EC2 instance IP address."
  echo "Please provide it with --ip or ensure Terraform outputs are available."
  exit 1
fi

echo_info "EC2 IP: ${EC2_IP}"

# Run deployment
deploy "$EC2_IP"

echo ""
echo_info "=== Deployment Complete ==="
echo "Gateway URL: http://${EC2_IP}:18789"
echo "SSH: ssh ${EC2_USER}@${EC2_IP}"
echo "Logs: ssh ${EC2_USER}@${EC2_IP} 'journalctl -u openclaw-gateway -f'"
