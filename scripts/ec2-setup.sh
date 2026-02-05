#!/usr/bin/env bash
set -euo pipefail

# EC2 Setup Script
# One-time setup script to run on the EC2 instance after Terraform provisioning.
# This clones the repo and starts the OpenClaw gateway service.

# Configuration (can override via env vars)
REPO_URL="${REPO_URL:-https://github.com/openclaw/openclaw.git}"
BRANCH="${BRANCH:-main}"
INSTALL_DIR="${INSTALL_DIR:-/home/ec2-user/openclaw}"

echo "=== OpenClaw EC2 Setup ==="
echo "Repo: ${REPO_URL}"
echo "Branch: ${BRANCH}"
echo "Install dir: ${INSTALL_DIR}"

# Ensure we're running as ec2-user or with correct permissions
if [[ "$(whoami)" == "root" ]]; then
  echo "Running as root, switching to ec2-user for git operations..."
  SUDO_PREFIX="sudo -u ec2-user"
else
  SUDO_PREFIX=""
fi

# Clone or update the repository
if [[ -d "${INSTALL_DIR}/.git" ]]; then
  echo "Repository exists, pulling latest changes..."
  cd "${INSTALL_DIR}"
  $SUDO_PREFIX git fetch origin
  $SUDO_PREFIX git checkout "${BRANCH}"
  $SUDO_PREFIX git pull origin "${BRANCH}"
else
  echo "Cloning repository..."
  $SUDO_PREFIX git clone --branch "${BRANCH}" "${REPO_URL}" "${INSTALL_DIR}"
  cd "${INSTALL_DIR}"
fi

# Install dependencies
echo "Installing dependencies..."
cd "${INSTALL_DIR}"
$SUDO_PREFIX npm install --omit=dev

# Build the project
echo "Building project..."
$SUDO_PREFIX npm run build

# Load secrets (this creates /etc/openclaw/env)
echo "Loading secrets from AWS Secrets Manager..."
sudo /usr/local/bin/openclaw-load-secrets.sh

# Start the service
echo "Starting OpenClaw gateway service..."
sudo systemctl daemon-reload
sudo systemctl restart openclaw-gateway

# Wait for service to start
echo "Waiting for service to start..."
sleep 5

# Check service status
if systemctl is-active --quiet openclaw-gateway; then
  echo "OpenClaw gateway service is running!"

  # Get the port from the environment file
  PORT=$(grep "^PORT=" /etc/openclaw/env | cut -d= -f2)

  # Health check
  echo "Performing health check..."
  if curl -sf "http://localhost:${PORT}/health" > /dev/null 2>&1; then
    echo "Health check passed!"
  else
    echo "Warning: Health check failed. Check logs with: journalctl -u openclaw-gateway -f"
  fi
else
  echo "Error: OpenClaw gateway service failed to start!"
  echo "Check logs with: journalctl -u openclaw-gateway -f"
  exit 1
fi

echo ""
echo "=== Setup Complete ==="
echo "View logs: journalctl -u openclaw-gateway -f"
echo "Service status: systemctl status openclaw-gateway"
echo "Restart service: sudo systemctl restart openclaw-gateway"
