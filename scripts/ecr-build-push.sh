#!/usr/bin/env bash
set -euo pipefail

# ECR Build and Push Script
# Builds the OpenClaw Docker image and pushes to ECR for ECS Fargate deployment.

# Configuration (can override via env vars)
AWS_REGION="${AWS_REGION:-us-west-2}"
AWS_PROFILE="${AWS_PROFILE:-default}"
ENVIRONMENT="${ENVIRONMENT:-prod}"
DEPLOY="${DEPLOY:-true}"
ECS_CLUSTER="openclaw-prod-cluster"
ECS_SERVICE="openclaw-prod-service"

# Get account ID and construct ECR URL
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/openclaw-${ENVIRONMENT}"

echo "Building and pushing to: ${ECR_REPO}"

# Login to ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Build with linux/amd64 platform for Fargate compatibility
echo "Building Docker image (linux/amd64)..."
docker build --platform linux/amd64 -t "openclaw-${ENVIRONMENT}" .

# Tag and push
echo "Tagging and pushing..."
docker tag "openclaw-${ENVIRONMENT}:latest" "${ECR_REPO}:latest"
docker push "${ECR_REPO}:latest"

echo "Successfully pushed ${ECR_REPO}:latest"

# Force new deployment to ECS
if [ "$DEPLOY" = true ]; then
  echo "Forcing new ECS deployment..."
  aws ecs update-service \
    --cluster "${ECS_CLUSTER}" \
    --service "${ECS_SERVICE}" \
    --force-new-deployment \
    --region "${AWS_REGION}" \
    --profile "${AWS_PROFILE}" \
    --no-cli-pager

  echo "Deployment initiated. Waiting for service to stabilize..."
  aws ecs wait services-stable \
    --cluster "${ECS_CLUSTER}" \
    --services "${ECS_SERVICE}" \
    --region "${AWS_REGION}" \
    --profile "${AWS_PROFILE}"

  echo "Deployment complete!"
fi
