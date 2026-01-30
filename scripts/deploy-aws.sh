#!/bin/bash
# AWS Deployment Script for Giga MST
# Usage: ./scripts/deploy-aws.sh [command]
# Commands: setup, build, push, deploy, init, status, logs

set -euo pipefail

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
STACK_NAME="${STACK_NAME:-giga-mst}"
ECR_REPO_SUPERSET="giga-mst/superset"
ECR_REPO_DATABASE="giga-mst/database"
ECS_CLUSTER="${STACK_NAME}-cluster"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install it first."
        exit 1
    fi
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found. Please install it first."
        exit 1
    fi
    
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        log_error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    log_info "Prerequisites OK. AWS Account: $AWS_ACCOUNT_ID, Region: $AWS_REGION"
}

setup_infrastructure() {
    log_info "Setting up AWS infrastructure with CloudFormation..."
    
    aws cloudformation create-stack \
        --stack-name "${STACK_NAME}-vpc" \
        --template-body file://cloudformation/vpc.yaml \
        --parameters ParameterKey=EnvironmentName,ParameterValue="$STACK_NAME" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$AWS_REGION"
    
    log_info "Waiting for stack creation to complete..."
    aws cloudformation wait stack-create-complete \
        --stack-name "${STACK_NAME}-vpc" \
        --region "$AWS_REGION"
    
    log_info "Infrastructure setup complete!"
    
    # Display outputs
    aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}-vpc" \
        --query 'Stacks[0].Outputs' \
        --output table \
        --region "$AWS_REGION"
}

create_ecr_repos() {
    log_info "Creating ECR repositories..."
    
    aws ecr create-repository \
        --repository-name "$ECR_REPO_SUPERSET" \
        --region "$AWS_REGION" 2>/dev/null || log_warn "Repository $ECR_REPO_SUPERSET already exists"
    
    aws ecr create-repository \
        --repository-name "$ECR_REPO_DATABASE" \
        --region "$AWS_REGION" 2>/dev/null || log_warn "Repository $ECR_REPO_DATABASE already exists"
    
    log_info "ECR repositories ready"
}

ecr_login() {
    log_info "Logging into ECR..."
    aws ecr get-login-password --region "$AWS_REGION" | \
        docker login --username AWS --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
}

build_images() {
    log_info "Building Docker images..."
    
    # Build Superset image
    log_info "Building Superset image..."
    docker build -t "$ECR_REPO_SUPERSET:latest" .
    
    # Build Database image
    log_info "Building Database image..."
    docker build -t "$ECR_REPO_DATABASE:latest" ./database
    
    log_info "Docker images built successfully"
}

push_images() {
    ecr_login
    
    local IMAGE_TAG="${1:-latest}"
    local ECR_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
    
    log_info "Pushing images with tag: $IMAGE_TAG"
    
    # Tag and push Superset
    docker tag "$ECR_REPO_SUPERSET:latest" "$ECR_URI/$ECR_REPO_SUPERSET:$IMAGE_TAG"
    docker push "$ECR_URI/$ECR_REPO_SUPERSET:$IMAGE_TAG"
    
    if [ "$IMAGE_TAG" != "latest" ]; then
        docker tag "$ECR_REPO_SUPERSET:latest" "$ECR_URI/$ECR_REPO_SUPERSET:latest"
        docker push "$ECR_URI/$ECR_REPO_SUPERSET:latest"
    fi
    
    # Tag and push Database
    docker tag "$ECR_REPO_DATABASE:latest" "$ECR_URI/$ECR_REPO_DATABASE:$IMAGE_TAG"
    docker push "$ECR_URI/$ECR_REPO_DATABASE:$IMAGE_TAG"
    
    log_info "Images pushed to ECR successfully"
}

deploy_services() {
    log_info "Deploying ECS services..."
    
    # Force new deployment for all services
    aws ecs update-service \
        --cluster "$ECS_CLUSTER" \
        --service superset \
        --force-new-deployment \
        --region "$AWS_REGION" || log_warn "Service 'superset' not found or update failed"
    
    aws ecs update-service \
        --cluster "$ECS_CLUSTER" \
        --service celery-worker \
        --force-new-deployment \
        --region "$AWS_REGION" || log_warn "Service 'celery-worker' not found or update failed"
    
    aws ecs update-service \
        --cluster "$ECS_CLUSTER" \
        --service celery-beat \
        --force-new-deployment \
        --region "$AWS_REGION" || log_warn "Service 'celery-beat' not found or update failed"
    
    log_info "Deployment triggered. Use 'status' command to monitor progress."
}

init_superset() {
    log_info "Running Superset initialization task..."
    
    # Get task definition ARN
    local TASK_DEF=$(aws ecs describe-services \
        --cluster "$ECS_CLUSTER" \
        --services superset \
        --query 'services[0].taskDefinition' \
        --output text \
        --region "$AWS_REGION")
    
    # Get network configuration from service
    local SUBNETS=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}-vpc" \
        --query 'Stacks[0].Outputs[?OutputKey==`PublicSubnet1Id`].OutputValue' \
        --output text \
        --region "$AWS_REGION")
    
    local SECURITY_GROUP=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}-vpc" \
        --query 'Stacks[0].Outputs[?OutputKey==`ECSSecurityGroupId`].OutputValue' \
        --output text \
        --region "$AWS_REGION")
    
    aws ecs run-task \
        --cluster "$ECS_CLUSTER" \
        --task-definition "$TASK_DEF" \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SECURITY_GROUP],assignPublicIp=ENABLED}" \
        --overrides '{"containerOverrides":[{"name":"superset","command":["/docker/superset-init.sh"]}]}' \
        --region "$AWS_REGION"
    
    log_info "Initialization task started. Check CloudWatch logs for progress."
}

show_status() {
    log_info "ECS Cluster Status:"
    
    aws ecs describe-services \
        --cluster "$ECS_CLUSTER" \
        --services superset celery-worker celery-beat \
        --query 'services[].{Service:serviceName,Status:status,Running:runningCount,Desired:desiredCount,Pending:pendingCount}' \
        --output table \
        --region "$AWS_REGION" 2>/dev/null || log_warn "Could not retrieve service status"
}

show_logs() {
    local SERVICE="${1:-superset}"
    log_info "Showing recent logs for $SERVICE..."
    
    aws logs tail "/ecs/$STACK_NAME" \
        --filter-pattern "$SERVICE" \
        --since 30m \
        --region "$AWS_REGION" || log_warn "Could not retrieve logs"
}

usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  setup     - Create AWS infrastructure (VPC, subnets, security groups, ECS cluster)"
    echo "  ecr       - Create ECR repositories"
    echo "  build     - Build Docker images locally"
    echo "  push      - Push images to ECR (optional: TAG as argument)"
    echo "  deploy    - Deploy/update ECS services"
    echo "  init      - Run Superset initialization (create admin, db migrate)"
    echo "  status    - Show ECS service status"
    echo "  logs      - Show recent logs (optional: SERVICE as argument)"
    echo "  full      - Run full deployment (setup + ecr + build + push + deploy)"
    echo ""
    echo "Environment variables:"
    echo "  AWS_REGION     - AWS region (default: us-east-1)"
    echo "  STACK_NAME     - CloudFormation stack name prefix (default: giga-mst)"
}

# Main
case "${1:-help}" in
    setup)
        check_prerequisites
        setup_infrastructure
        ;;
    ecr)
        check_prerequisites
        create_ecr_repos
        ;;
    build)
        check_prerequisites
        build_images
        ;;
    push)
        check_prerequisites
        push_images "${2:-latest}"
        ;;
    deploy)
        check_prerequisites
        deploy_services
        ;;
    init)
        check_prerequisites
        init_superset
        ;;
    status)
        check_prerequisites
        show_status
        ;;
    logs)
        check_prerequisites
        show_logs "${2:-superset}"
        ;;
    full)
        check_prerequisites
        setup_infrastructure
        create_ecr_repos
        build_images
        push_images "$(git rev-parse --short HEAD 2>/dev/null || echo 'latest')"
        deploy_services
        log_info "Full deployment complete! Run 'init' to initialize Superset."
        ;;
    help|*)
        usage
        ;;
esac
