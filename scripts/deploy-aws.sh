#!/bin/bash
# AWS Deployment Script for Giga MST
# Usage: ./scripts/deploy-aws.sh [command]
# Commands: setup, build, push, deploy, init, status, logs

set -euo pipefail

# Configuration
AWS_REGION="${AWS_REGION:-eu-west-1}"
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

ensure_secrets() {
    log_info "Ensuring required Secrets Manager secrets exist (database, superset, superset-admin, mapbox, smtp)..."

    # DB creds used for both RDS instances
    if ! aws secretsmanager describe-secret --secret-id "${STACK_NAME}/database" --region "$AWS_REGION" >/dev/null 2>&1; then
        log_info "Creating secret ${STACK_NAME}/database"
        aws secretsmanager create-secret \
          --name "${STACK_NAME}/database" \
          --generate-secret-string '{"SecretStringTemplate":"{\"username\":\"giga_admin\"}","GenerateStringKey":"password","PasswordLength":32,"ExcludePunctuation":true}' \
          --region "$AWS_REGION" >/dev/null
    fi

    # Superset secret key
    if ! aws secretsmanager describe-secret --secret-id "${STACK_NAME}/superset" --region "$AWS_REGION" >/dev/null 2>&1; then
        log_info "Creating secret ${STACK_NAME}/superset"
        aws secretsmanager create-secret \
          --name "${STACK_NAME}/superset" \
          --generate-secret-string '{"SecretStringTemplate":"{}","GenerateStringKey":"secret_key","PasswordLength":64,"ExcludePunctuation":true}' \
          --region "$AWS_REGION" >/dev/null
    fi

    # Mapbox API key (optional but recommended for map visuals)
    # - If the secret doesn't exist, create it (empty by default).
    # - If MAPBOX_API_KEY is set in your environment, always update the secret value.
    if ! aws secretsmanager describe-secret --secret-id "${STACK_NAME}/mapbox" --region "$AWS_REGION" >/dev/null 2>&1; then
        log_info "Creating secret ${STACK_NAME}/mapbox"
        aws secretsmanager create-secret \
          --name "${STACK_NAME}/mapbox" \
          --secret-string '{"api_key":""}' \
          --region "$AWS_REGION" >/dev/null
    fi

    if [ -n "${MAPBOX_API_KEY:-}" ]; then
        log_info "Updating secret ${STACK_NAME}/mapbox from MAPBOX_API_KEY env var"
        local MAPBOX_SECRET_JSON
        MAPBOX_SECRET_JSON=$(python3 - <<"PY"
import json, os
print(json.dumps({"api_key": os.environ["MAPBOX_API_KEY"]}))
PY
)
        aws secretsmanager put-secret-value \
          --secret-id "${STACK_NAME}/mapbox" \
          --secret-string "$MAPBOX_SECRET_JSON" \
          --region "$AWS_REGION" >/dev/null
    fi

    # SMTP credentials for reports/alerts (optional; set SMTP_USER/SMTP_PASSWORD in env to populate)
    if ! aws secretsmanager describe-secret --secret-id "${STACK_NAME}/smtp" --region "$AWS_REGION" >/dev/null 2>&1; then
        log_info "Creating secret ${STACK_NAME}/smtp"
        aws secretsmanager create-secret \
          --name "${STACK_NAME}/smtp" \
          --secret-string '{"username":"","password":""}' \
          --region "$AWS_REGION" >/dev/null
    fi

    if [ -n "${SMTP_USER:-}" ] || [ -n "${SMTP_PASSWORD:-}" ]; then
        if [ -z "${SMTP_USER:-}" ] || [ -z "${SMTP_PASSWORD:-}" ]; then
            log_warn "SMTP_USER/SMTP_PASSWORD: one is missing; not updating ${STACK_NAME}/smtp"
        else
            log_info "Updating secret ${STACK_NAME}/smtp from SMTP_USER/SMTP_PASSWORD env vars"
            local SMTP_SECRET_JSON
            SMTP_SECRET_JSON=$(python3 - <<"PY"
import json, os
print(json.dumps({"username": os.environ["SMTP_USER"], "password": os.environ["SMTP_PASSWORD"]}))
PY
)
            aws secretsmanager put-secret-value \
              --secret-id "${STACK_NAME}/smtp" \
              --secret-string "$SMTP_SECRET_JSON" \
              --region "$AWS_REGION" >/dev/null
        fi
    fi

    # Admin login for Superset UI
    if ! aws secretsmanager describe-secret --secret-id "${STACK_NAME}/superset-admin" --region "$AWS_REGION" >/dev/null 2>&1; then
        log_info "Creating secret ${STACK_NAME}/superset-admin"
        aws secretsmanager create-secret \
          --name "${STACK_NAME}/superset-admin" \
          --generate-secret-string '{"SecretStringTemplate":"{\"username\":\"admin\"}","GenerateStringKey":"password","PasswordLength":24,"ExcludePunctuation":true}' \
          --region "$AWS_REGION" >/dev/null
    fi

    log_info "Secrets ready."
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

    log_info "Building and pushing linux/amd64 images with tag: $IMAGE_TAG"
    log_info "(This avoids 'exec format error' when deploying from Apple Silicon to Fargate/x86_64.)"

    # Build+push Superset image
    docker buildx build \
        --platform linux/amd64 \
        -t "$ECR_URI/$ECR_REPO_SUPERSET:$IMAGE_TAG" \
        -t "$ECR_URI/$ECR_REPO_SUPERSET:latest" \
        --push \
        .

    # Build+push Database loader image (used for one-off data loading into RDS)
    docker buildx build \
        --platform linux/amd64 \
        -t "$ECR_URI/$ECR_REPO_DATABASE:$IMAGE_TAG" \
        -t "$ECR_URI/$ECR_REPO_DATABASE:latest" \
        --push \
        ./database

    log_info "Images built and pushed to ECR successfully"
}

deploy_services_stack() {
    log_info "Deploying services stack (RDS, Redis, ALB, ECS services) with CloudFormation..."

    ensure_secrets

    local SERVICES_STACK="${STACK_NAME}-services"

    local DB_SECRET_ARN=$(aws secretsmanager describe-secret --secret-id "${STACK_NAME}/database" --query 'ARN' --output text --region "$AWS_REGION")
    local SUPERSET_SECRET_ARN=$(aws secretsmanager describe-secret --secret-id "${STACK_NAME}/superset" --query 'ARN' --output text --region "$AWS_REGION")
    local SUPERSET_ADMIN_SECRET_ARN=$(aws secretsmanager describe-secret --secret-id "${STACK_NAME}/superset-admin" --query 'ARN' --output text --region "$AWS_REGION")
    local MAPBOX_SECRET_ARN=$(aws secretsmanager describe-secret --secret-id "${STACK_NAME}/mapbox" --query 'ARN' --output text --region "$AWS_REGION")
    local SMTP_SECRET_ARN=$(aws secretsmanager describe-secret --secret-id "${STACK_NAME}/smtp" --query 'ARN' --output text --region "$AWS_REGION")

    local CFN_PARAMS=(
      "ParameterKey=EnvironmentName,ParameterValue=$STACK_NAME"
      "ParameterKey=DatabaseSecretArn,ParameterValue=$DB_SECRET_ARN"
      "ParameterKey=SupersetSecretArn,ParameterValue=$SUPERSET_SECRET_ARN"
      "ParameterKey=SupersetAdminSecretArn,ParameterValue=$SUPERSET_ADMIN_SECRET_ARN"
      "ParameterKey=MapboxSecretArn,ParameterValue=$MAPBOX_SECRET_ARN"
      "ParameterKey=SmtpSecretArn,ParameterValue=$SMTP_SECRET_ARN"
    )

    if aws cloudformation describe-stacks --stack-name "$SERVICES_STACK" --region "$AWS_REGION" >/dev/null 2>&1; then
        log_info "Updating existing stack: $SERVICES_STACK"
        aws cloudformation update-stack \
            --stack-name "$SERVICES_STACK" \
            --template-body file://cloudformation/services.yaml \
            --parameters "${CFN_PARAMS[@]}" \
            --capabilities CAPABILITY_NAMED_IAM \
            --region "$AWS_REGION" \
          || log_warn "No changes to apply (or update failed)"

        log_info "Waiting for stack update to complete..."
        aws cloudformation wait stack-update-complete \
            --stack-name "$SERVICES_STACK" \
            --region "$AWS_REGION" \
          || log_warn "Stack update wait ended (check CloudFormation events if needed)"
    else
        log_info "Creating new stack: $SERVICES_STACK"
        aws cloudformation create-stack \
            --stack-name "$SERVICES_STACK" \
            --template-body file://cloudformation/services.yaml \
            --parameters "${CFN_PARAMS[@]}" \
            --capabilities CAPABILITY_NAMED_IAM \
            --region "$AWS_REGION"

        log_info "Waiting for stack creation to complete..."
        aws cloudformation wait stack-create-complete \
            --stack-name "$SERVICES_STACK" \
            --region "$AWS_REGION"
    fi

    log_info "Services stack deploy completed."
}

load_data() {
    log_info "Loading MST data into the DataDB RDS instance (idempotent)..."

    local SERVICES_STACK="${STACK_NAME}-services"
    local DATA_HOST=$(aws cloudformation describe-stacks \
        --stack-name "$SERVICES_STACK" \
        --query "Stacks[0].Outputs[?OutputKey=='DataDBEndpoint'].OutputValue" \
        --output text \
        --region "$AWS_REGION")

    if [ -z "$DATA_HOST" ] || [ "$DATA_HOST" = "None" ]; then
        log_error "Could not determine DataDBEndpoint from CloudFormation stack outputs."
        exit 1
    fi

    local DB_NAME="giga_mst"
    local DB_PORT="5432"

    # Resolve the Secrets Manager ARN (so we don't bake in the random suffix)
    local DB_SECRET_ARN=$(aws secretsmanager describe-secret \
        --secret-id "${STACK_NAME}/database" \
        --query 'ARN' \
        --output text \
        --region "$AWS_REGION")

    local EXEC_ROLE=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}-vpc" \
        --query "Stacks[0].Outputs[?OutputKey=='ECSTaskExecutionRoleArn'].OutputValue" \
        --output text \
        --region "$AWS_REGION")

    local TASK_ROLE=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}-vpc" \
        --query "Stacks[0].Outputs[?OutputKey=='ECSTaskRoleArn'].OutputValue" \
        --output text \
        --region "$AWS_REGION")

    local ECR_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
    local LOADER_IMAGE="$ECR_URI/$ECR_REPO_DATABASE:latest"

    log_info "Registering/using DB loader task definition (image: $LOADER_IMAGE)"

    # Build container definitions JSON carefully:
    # - outer values (image, endpoints) are substituted now
    # - runtime secrets/env vars (DATABASE_PASSWORD, etc.) must NOT be expanded by this script
    local CONTAINER_DEFS
    CONTAINER_DEFS=$(cat <<EOF
[{
  "name": "db-loader",
  "image": "$LOADER_IMAGE",
  "essential": true,
  "command": [
    "bash",
    "-lc",
    "set -euo pipefail; \
export PGPASSWORD=\"\$DATABASE_PASSWORD\"; \
EXISTS=\$(psql -tAc \"SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='school';\" \"host=\$POSTGIS_HOST port=\$POSTGIS_PORT user=\$DATABASE_USER dbname=\$POSTGIS_DB\" || true); \
if [ \"\$EXISTS\" = \"1\" ]; then echo '[INFO] MST tables already exist; skipping load.'; exit 0; fi; \
echo '[INFO] Loading MST schema + CSVs into RDS...'; \
psql -v ON_ERROR_STOP=1 \"host=\$POSTGIS_HOST port=\$POSTGIS_PORT user=\$DATABASE_USER dbname=\$POSTGIS_DB\" -f /docker-entrypoint-initdb.d/init.sql"
  ],
  "environment": [
    {"name": "POSTGIS_HOST", "value": "$DATA_HOST"},
    {"name": "POSTGIS_PORT", "value": "$DB_PORT"},
    {"name": "POSTGIS_DB", "value": "$DB_NAME"}
  ],
  "secrets": [
    {"name": "DATABASE_USER", "valueFrom": "$DB_SECRET_ARN:username::"},
    {"name": "DATABASE_PASSWORD", "valueFrom": "$DB_SECRET_ARN:password::"}
  ],
  "logConfiguration": {
    "logDriver": "awslogs",
    "options": {
      "awslogs-group": "/ecs/$STACK_NAME",
      "awslogs-region": "$AWS_REGION",
      "awslogs-stream-prefix": "db-loader"
    }
  }
}]
EOF
)

    local TD_ARN=$(aws ecs register-task-definition \
      --family "${STACK_NAME}-db-loader" \
      --requires-compatibilities FARGATE \
      --network-mode awsvpc \
      --cpu "512" \
      --memory "1024" \
      --execution-role-arn "$EXEC_ROLE" \
      --task-role-arn "$TASK_ROLE" \
      --container-definitions "$CONTAINER_DEFS" \
      --query 'taskDefinition.taskDefinitionArn' \
      --output text \
      --region "$AWS_REGION")

    local SUBNETS=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}-vpc" \
        --query "Stacks[0].Outputs[?OutputKey=='PrivateSubnet1Id' || OutputKey=='PrivateSubnet2Id'].OutputValue" \
        --output text \
        --region "$AWS_REGION" | tr '\t' ',')

    local SECURITY_GROUP=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}-vpc" \
        --query "Stacks[0].Outputs[?OutputKey=='ECSSecurityGroupId'].OutputValue" \
        --output text \
        --region "$AWS_REGION")

    log_info "Running one-off DB loader task..."
    local TASK_ARN=$(aws ecs run-task \
      --cluster "$ECS_CLUSTER" \
      --task-definition "$TD_ARN" \
      --launch-type FARGATE \
      --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SECURITY_GROUP],assignPublicIp=DISABLED}" \
      --query 'tasks[0].taskArn' \
      --output text \
      --region "$AWS_REGION")

    aws ecs wait tasks-stopped --cluster "$ECS_CLUSTER" --tasks "$TASK_ARN" --region "$AWS_REGION"

    log_info "DB loader task finished. Check CloudWatch log streams with prefix db-loader if needed."
}

deploy_services() {
    log_info "Deploying ECS services..."

    local SUPERSET_SERVICE="${STACK_NAME}-superset"
    local CELERY_WORKER_SERVICE="${STACK_NAME}-celery-worker"
    local CELERY_BEAT_SERVICE="${STACK_NAME}-celery-beat"

    # Force new deployment for all services
    aws ecs update-service \
        --cluster "$ECS_CLUSTER" \
        --service "$SUPERSET_SERVICE" \
        --force-new-deployment \
        --region "$AWS_REGION" || log_warn "Service '$SUPERSET_SERVICE' not found or update failed"

    aws ecs update-service \
        --cluster "$ECS_CLUSTER" \
        --service "$CELERY_WORKER_SERVICE" \
        --force-new-deployment \
        --region "$AWS_REGION" || log_warn "Service '$CELERY_WORKER_SERVICE' not found or update failed"

    aws ecs update-service \
        --cluster "$ECS_CLUSTER" \
        --service "$CELERY_BEAT_SERVICE" \
        --force-new-deployment \
        --region "$AWS_REGION" || log_warn "Service '$CELERY_BEAT_SERVICE' not found or update failed"

    log_info "Deployment triggered. Use 'status' command to monitor progress."
}

init_superset() {
    log_info "Running Superset initialization task..."

    local SUPERSET_SERVICE="${STACK_NAME}-superset"

    # Get task definition ARN from the running service
    local TASK_DEF=$(aws ecs describe-services \
        --cluster "$ECS_CLUSTER" \
        --services "$SUPERSET_SERVICE" \
        --query 'services[0].taskDefinition' \
        --output text \
        --region "$AWS_REGION")

    # Run init task in the same VPC private subnets as ECS services
    local SUBNETS=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}-vpc" \
        --query "Stacks[0].Outputs[?OutputKey=='PrivateSubnet1Id' || OutputKey=='PrivateSubnet2Id'].OutputValue" \
        --output text \
        --region "$AWS_REGION" | tr '\t' ',')

    local SECURITY_GROUP=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}-vpc" \
        --query "Stacks[0].Outputs[?OutputKey=='ECSSecurityGroupId'].OutputValue" \
        --output text \
        --region "$AWS_REGION")

    aws ecs run-task \
        --cluster "$ECS_CLUSTER" \
        --task-definition "$TASK_DEF" \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SECURITY_GROUP],assignPublicIp=DISABLED}" \
        --overrides '{"containerOverrides":[{"name":"superset","command":["/docker/superset-init.sh"],"environment":[{"name":"SUPERSET_IMPORT_MST_ASSETS","value":"1"},{"name":"SUPERSET_MST_DB_NAME","value":"PostgreSQL"}]}]}' \
        --region "$AWS_REGION"

    log_info "Initialization task started. Check CloudWatch logs for progress."
}

show_status() {
    log_info "ECS Cluster Status:"

    aws ecs describe-services \
        --cluster "$ECS_CLUSTER" \
        --services "${STACK_NAME}-superset" "${STACK_NAME}-celery-worker" "${STACK_NAME}-celery-beat" \
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
    echo "  deploy    - Force new deployment on ECS services"
    echo "  services  - Create/update the CloudFormation services stack (RDS/Redis/ALB/ECS)"
    echo "  init      - Run Superset initialization (create admin, db migrate)"
    echo "  load-data - Load MST schema+CSVs into the DataDB RDS instance (skips if already loaded)"
    echo "  status    - Show ECS service status"
    echo "  logs      - Show recent logs (optional: SERVICE as argument)"
    echo "  full      - Run full deployment (setup + ecr + push + services + load-data + deploy)"
    echo ""
    echo "Environment variables:"
    echo "  AWS_REGION     - AWS region (default: eu-west-1)"
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
    services)
        check_prerequisites
        deploy_services_stack
        ;;
    deploy)
        check_prerequisites
        deploy_services
        ;;
    init)
        check_prerequisites
        init_superset
        ;;
    load-data)
        check_prerequisites
        load_data
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
        push_images "$(git rev-parse --short HEAD 2>/dev/null || echo 'latest')"
        deploy_services_stack
        load_data
        deploy_services
        log_info "Full deployment complete! Run 'init' to initialize Superset."
        ;;
    help|*)
        usage
        ;;
esac
