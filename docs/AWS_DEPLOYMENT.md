# AWS Deployment Guide - Giga Mobile Simulation Tool

This document provides deployment instructions for the Giga MST Superset application on AWS.

## Table of Contents
- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Option 1: AWS ECS with Fargate (Recommended)](#option-1-aws-ecs-with-fargate-recommended)
- [Option 2: AWS EC2 with Docker Compose](#option-2-aws-ec2-with-docker-compose)
- [Database Options](#database-options)
- [Secrets Management](#secrets-management)
- [Load Balancer & SSL](#load-balancer--ssl)
- [Monitoring & Logging](#monitoring--logging)
- [Cost Estimation](#cost-estimation)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AWS Cloud                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌───────────────┐                                                          │
│  │  Route 53     │ ─── DNS                                                  │
│  └───────┬───────┘                                                          │
│          │                                                                   │
│  ┌───────▼───────┐                                                          │
│  │     ALB       │ ─── Application Load Balancer (HTTPS)                    │
│  └───────┬───────┘                                                          │
│          │                                                                   │
│  ┌───────▼───────────────────────────────────────────────────────────────┐  │
│  │                         ECS Cluster (Fargate)                          │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                    │  │
│  │  │  Superset   │  │   Celery    │  │   Celery    │                    │  │
│  │  │    App      │  │   Worker    │  │    Beat     │                    │  │
│  │  │  (2 tasks)  │  │  (2 tasks)  │  │  (1 task)   │                    │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                    │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│          │                    │                    │                         │
│  ┌───────▼──────┐   ┌────────▼────────┐   ┌──────▼──────┐                   │
│  │ RDS PostgreSQL│   │ ElastiCache    │   │ RDS PostGIS │                   │
│  │  (Metadata)   │   │   (Redis)      │   │   (Data)    │                   │
│  └───────────────┘   └────────────────┘   └─────────────┘                   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                      Supporting Services                              │   │
│  │  • ECR (Container Registry)  • Secrets Manager  • CloudWatch         │   │
│  │  • S3 (Backups/Assets)       • ACM (SSL Certs)  • VPC & Subnets      │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

### AWS CLI & Tools
```bash
# Install AWS CLI
brew install awscli  # macOS
# Configure credentials
aws configure

# Install ECS CLI (optional)
brew install amazon-ecs-cli

# Install Docker
brew install --cask docker
```

### Required AWS Permissions
- ECS Full Access
- ECR Full Access  
- RDS Full Access
- ElastiCache Full Access
- VPC Full Access
- IAM Role Creation
- Secrets Manager Access
- CloudWatch Logs Access

---

## Option 1: AWS ECS with Fargate (Recommended)

Recommended approach (repo helper script):
```bash
./scripts/deploy-aws.sh full       # includes load-data
./scripts/deploy-aws.sh init       # sets admin password + imports MST dashboards
```

Notes:
- The script builds/pushes linux/amd64 images to avoid Apple Silicon -> Fargate "exec format error".
- The init step skips `superset load_examples` by default; it imports the MST dashboard export instead.

### Step 1: Create ECR Repositories

```bash
# Set variables
AWS_REGION=us-east-1
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create repositories
aws ecr create-repository --repository-name giga-mst/superset --region $AWS_REGION
aws ecr create-repository --repository-name giga-mst/database --region $AWS_REGION

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
```

### Step 2: Build and Push Images

```bash
# Build and push Superset image
docker build -t giga-mst/superset:latest .
docker tag giga-mst/superset:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/giga-mst/superset:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/giga-mst/superset:latest

# Build and push Database image (for initial data load)
docker build -t giga-mst/database:latest ./database
docker tag giga-mst/database:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/giga-mst/database:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/giga-mst/database:latest
```

### Step 3: Create VPC Infrastructure

Use the provided CloudFormation template or create manually:

Note on example data:
- For AWS/prod deployments, the init script skips `superset load_examples` by default.
- If you *do* want example dashboards/data (not recommended for prod), set `SUPERSET_LOAD_EXAMPLES=1` for the one-off init task.

```bash
aws cloudformation create-stack \
  --stack-name giga-mst-vpc \
  --template-body file://cloudformation/vpc.yaml \
  --capabilities CAPABILITY_IAM
```

### Step 4: Create RDS Instances

```bash
# Metadata DB (PostgreSQL)
aws rds create-db-instance \
  --db-instance-identifier giga-mst-metadata \
  --db-instance-class db.t3.small \
  --engine postgres \
  --engine-version 16.11 \
  --master-username superset \
  --master-user-password <secure-password> \
  --allocated-storage 20 \
  --vpc-security-group-ids <sg-id> \
  --db-subnet-group-name <subnet-group> \
  --db-name superset

# Data DB (PostGIS) - use db.t3.medium or larger for geospatial queries
aws rds create-db-instance \
  --db-instance-identifier giga-mst-data \
  --db-instance-class db.t3.medium \
  --engine postgres \
  --engine-version 16.11 \
  --master-username postgres \
  --master-user-password <secure-password> \
  --allocated-storage 50 \
  --vpc-security-group-ids <sg-id> \
  --db-subnet-group-name <subnet-group> \
  --db-name mst
```

**Enable PostGIS Extension:**
```sql
-- Connect to the data RDS instance
CREATE EXTENSION IF NOT EXISTS postgis;
```

### Step 5: Create ElastiCache Redis

```bash
aws elasticache create-cache-cluster \
  --cache-cluster-id giga-mst-redis \
  --engine redis \
  --cache-node-type cache.t3.micro \
  --num-cache-nodes 1 \
  --security-group-ids <sg-id> \
  --cache-subnet-group-name <subnet-group>
```

### Step 6: Store Secrets in AWS Secrets Manager

If you're using `./scripts/deploy-aws.sh`, you usually don't need to manually create secrets — the script creates them for you.

Secrets created/used by the script (default `STACK_NAME=giga-mst`):
- `${STACK_NAME}/database` (JSON: `{"username": "...", "password": "..."}`) used for both RDS instances
- `${STACK_NAME}/superset` (JSON: `{"secret_key": "..."}`)
- `${STACK_NAME}/superset-admin` (JSON: `{"username": "admin", "password": "..."}`)
- `${STACK_NAME}/mapbox` (JSON: `{"api_key": "..."}`)

To set/update Mapbox for map visuals:
```bash
# Recommended: set env var in your shell, then run services (and deploy to restart tasks)
export MAPBOX_API_KEY=<your-mapbox-api-key>
./scripts/deploy-aws.sh services
./scripts/deploy-aws.sh deploy
```

### Step 7: Create ECS Task Definitions

Create `ecs/task-definition-superset.json`:

```json
{
  "family": "giga-mst-superset",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "1024",
  "memory": "2048",
  "executionRoleArn": "arn:aws:iam::<account-id>:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::<account-id>:role/ecsTaskRole",
  "containerDefinitions": [
    {
      "name": "superset",
      "image": "<account-id>.dkr.ecr.<region>.amazonaws.com/giga-mst/superset:latest",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 8088,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {"name": "SUPERSET_PORT", "value": "8088"},
        {"name": "SUPERSET_META_PORT", "value": "5432"},
        {"name": "SUPERSET_META_HOST", "value": "<rds-metadata-endpoint>"},
        {"name": "REDIS_HOST", "value": "<elasticache-endpoint>"},
        {"name": "REDIS_PORT", "value": "6379"},
        {"name": "CELERY_BROKER_URL", "value": "redis://<elasticache-endpoint>:6379/0"},
        {"name": "CELERY_RESULT_BACKEND", "value": "redis://<elasticache-endpoint>:6379/1"},
        {"name": "REDIS_CACHE_URL", "value": "redis://<elasticache-endpoint>:6379/0"}
      ],
      "secrets": [
        {"name": "SUPERSET_SECRET_KEY", "valueFrom": "arn:aws:secretsmanager:<region>:<account-id>:secret:giga-mst/superset:SUPERSET_SECRET_KEY::"},
        {"name": "SUPERSET_META_USER", "valueFrom": "arn:aws:secretsmanager:<region>:<account-id>:secret:giga-mst/superset:SUPERSET_META_USER::"},
        {"name": "SUPERSET_META_PASS", "valueFrom": "arn:aws:secretsmanager:<region>:<account-id>:secret:giga-mst/superset:SUPERSET_META_PASS::"},
        {"name": "MAPBOX_API_KEY", "valueFrom": "arn:aws:secretsmanager:<region>:<account-id>:secret:giga-mst/superset:MAPBOX_API_KEY::"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/giga-mst",
          "awslogs-region": "<region>",
          "awslogs-stream-prefix": "superset"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:8088/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3
      }
    }
  ]
}
```

Create `ecs/task-definition-celery-worker.json`:

```json
{
  "family": "giga-mst-celery-worker",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "1024",
  "memory": "2048",
  "executionRoleArn": "arn:aws:iam::<account-id>:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::<account-id>:role/ecsTaskRole",
  "containerDefinitions": [
    {
      "name": "celery-worker",
      "image": "<account-id>.dkr.ecr.<region>.amazonaws.com/giga-mst/superset:latest",
      "essential": true,
      "command": ["/docker/superset-celery.sh", "worker"],
      "user": "superset",
      "environment": [
        {"name": "SE_AVOID_SELENIUM_MANAGER", "value": "1"},
        {"name": "SE_DRIVER_PATH", "value": "/usr/bin/geckodriver"},
        {"name": "SUPERSET_META_PORT", "value": "5432"},
        {"name": "SUPERSET_META_HOST", "value": "<rds-metadata-endpoint>"},
        {"name": "REDIS_HOST", "value": "<elasticache-endpoint>"},
        {"name": "REDIS_PORT", "value": "6379"},
        {"name": "CELERY_BROKER_URL", "value": "redis://<elasticache-endpoint>:6379/0"},
        {"name": "CELERY_RESULT_BACKEND", "value": "redis://<elasticache-endpoint>:6379/1"}
      ],
      "secrets": [
        {"name": "SUPERSET_SECRET_KEY", "valueFrom": "arn:aws:secretsmanager:<region>:<account-id>:secret:giga-mst/superset:SUPERSET_SECRET_KEY::"},
        {"name": "SUPERSET_META_USER", "valueFrom": "arn:aws:secretsmanager:<region>:<account-id>:secret:giga-mst/superset:SUPERSET_META_USER::"},
        {"name": "SUPERSET_META_PASS", "valueFrom": "arn:aws:secretsmanager:<region>:<account-id>:secret:giga-mst/superset:SUPERSET_META_PASS::"},
        {"name": "SMTP_USER", "valueFrom": "arn:aws:secretsmanager:<region>:<account-id>:secret:giga-mst/superset:SMTP_USER::"},
        {"name": "SMTP_PASSWORD", "valueFrom": "arn:aws:secretsmanager:<region>:<account-id>:secret:giga-mst/superset:SMTP_PASSWORD::"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/giga-mst",
          "awslogs-region": "<region>",
          "awslogs-stream-prefix": "celery-worker"
        }
      }
    }
  ]
}
```

Create `ecs/task-definition-celery-beat.json`:

```json
{
  "family": "giga-mst-celery-beat",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::<account-id>:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::<account-id>:role/ecsTaskRole",
  "containerDefinitions": [
    {
      "name": "celery-beat",
      "image": "<account-id>.dkr.ecr.<region>.amazonaws.com/giga-mst/superset:latest",
      "essential": true,
      "command": ["/docker/superset-celery.sh", "beat"],
      "user": "superset",
      "environment": [
        {"name": "SE_AVOID_SELENIUM_MANAGER", "value": "1"},
        {"name": "SE_DRIVER_PATH", "value": "/usr/bin/geckodriver"},
        {"name": "SUPERSET_META_PORT", "value": "5432"},
        {"name": "SUPERSET_META_HOST", "value": "<rds-metadata-endpoint>"},
        {"name": "REDIS_HOST", "value": "<elasticache-endpoint>"},
        {"name": "REDIS_PORT", "value": "6379"},
        {"name": "CELERY_BROKER_URL", "value": "redis://<elasticache-endpoint>:6379/0"},
        {"name": "CELERY_RESULT_BACKEND", "value": "redis://<elasticache-endpoint>:6379/1"}
      ],
      "secrets": [
        {"name": "SUPERSET_SECRET_KEY", "valueFrom": "arn:aws:secretsmanager:<region>:<account-id>:secret:giga-mst/superset:SUPERSET_SECRET_KEY::"},
        {"name": "SUPERSET_META_USER", "valueFrom": "arn:aws:secretsmanager:<region>:<account-id>:secret:giga-mst/superset:SUPERSET_META_USER::"},
        {"name": "SUPERSET_META_PASS", "valueFrom": "arn:aws:secretsmanager:<region>:<account-id>:secret:giga-mst/superset:SUPERSET_META_PASS::"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/giga-mst",
          "awslogs-region": "<region>",
          "awslogs-stream-prefix": "celery-beat"
        }
      }
    }
  ]
}
```

### Step 8: Register Task Definitions

```bash
aws ecs register-task-definition --cli-input-json file://ecs/task-definition-superset.json
aws ecs register-task-definition --cli-input-json file://ecs/task-definition-celery-worker.json
aws ecs register-task-definition --cli-input-json file://ecs/task-definition-celery-beat.json
```

### Step 9: Create ECS Cluster and Services

```bash
# Create cluster
aws ecs create-cluster --cluster-name giga-mst-cluster

# Create CloudWatch log group
aws logs create-log-group --log-group-name /ecs/giga-mst

# Create Superset service
aws ecs create-service \
  --cluster giga-mst-cluster \
  --service-name superset \
  --task-definition giga-mst-superset \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[<subnet-1>,<subnet-2>],securityGroups=[<sg-id>],assignPublicIp=ENABLED}" \
  --load-balancers "targetGroupArn=<target-group-arn>,containerName=superset,containerPort=8088"

# Create Celery Worker service
aws ecs create-service \
  --cluster giga-mst-cluster \
  --service-name celery-worker \
  --task-definition giga-mst-celery-worker \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[<subnet-1>,<subnet-2>],securityGroups=[<sg-id>],assignPublicIp=ENABLED}"

# Create Celery Beat service (only 1 instance)
aws ecs create-service \
  --cluster giga-mst-cluster \
  --service-name celery-beat \
  --task-definition giga-mst-celery-beat \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[<subnet-1>,<subnet-2>],securityGroups=[<sg-id>],assignPublicIp=ENABLED}"
```

### Step 10: Initialize Superset (One-time)

Run initialization task:

```bash
aws ecs run-task \
  --cluster giga-mst-cluster \
  --task-definition giga-mst-superset \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[<subnet-1>],securityGroups=[<sg-id>],assignPublicIp=ENABLED}" \
  --overrides '{
    "containerOverrides": [{
      "name": "superset",
      "command": ["/docker/superset-init.sh"]
    }]
  }'
```

---

## Option 2: AWS EC2 with Docker Compose

For simpler deployments or development environments.

### Step 1: Launch EC2 Instance

```bash
# Launch Ubuntu 22.04 instance (t3.medium or larger recommended)
aws ec2 run-instances \
  --image-id ami-0c7217cdde317cfec \
  --instance-type t3.medium \
  --key-name <your-key-pair> \
  --security-group-ids <sg-id> \
  --subnet-id <subnet-id> \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":50,"VolumeType":"gp3"}}]' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=giga-mst}]'
```

### Step 2: Install Docker on EC2

```bash
# SSH into the instance
ssh -i <your-key.pem> ubuntu@<instance-ip>

# Install Docker
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker
```

### Step 3: Deploy Application

```bash
# Clone repository
git clone <your-repo-url> /home/ubuntu/mst
cd /home/ubuntu/mst

# Create environment files (use secure values)
# Edit env/.superset.env, env/.database.env, env/.metadata.env

# Initialize (first time only)
docker compose -f compose.init.yaml up --build

# Start production stack
docker compose up --build -d
```

### Step 4: Configure Nginx Reverse Proxy (Optional)

```bash
sudo apt-get install -y nginx

# Create Nginx config
sudo tee /etc/nginx/sites-available/superset << 'EOF'
server {
    listen 80;
    server_name your-domain.com;

    location / {
        proxy_pass http://localhost:8088;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

sudo ln -s /etc/nginx/sites-available/superset /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

---

## Database Options

### Option A: AWS RDS for PostgreSQL (Recommended for Production)

**Pros:** Managed backups, high availability, automated patching
**Cons:** Higher cost, limited PostGIS version control

```bash
# For PostGIS, enable the extension after creating RDS instance
psql -h <rds-endpoint> -U postgres -d mst -c "CREATE EXTENSION IF NOT EXISTS postgis;"

# Load initial data from CSV files
psql -h <rds-endpoint> -U postgres -d mst < database/init.sql
# Then use \COPY or AWS DMS for CSV data
```

### Option B: Self-Managed PostgreSQL on EC2

For maximum control over PostGIS configuration.

### Option C: Amazon Aurora PostgreSQL

Best for high-performance and scalability.

---

## Secrets Management

### Recommended: AWS Secrets Manager

```python
# Update superset_config.py for AWS Secrets Manager
import boto3
import json

def get_secret(secret_name):
    client = boto3.client('secretsmanager')
    response = client.get_secret_value(SecretId=secret_name)
    return json.loads(response['SecretString'])

# Use in config
secrets = get_secret('giga-mst/superset')
SECRET_KEY = secrets['SUPERSET_SECRET_KEY']
```

### Alternative: AWS Systems Manager Parameter Store

```bash
aws ssm put-parameter \
  --name "/giga-mst/superset-secret-key" \
  --value "<secret-key>" \
  --type "SecureString"
```

---

## Load Balancer & SSL

### Create Application Load Balancer

```bash
# Create target group
aws elbv2 create-target-group \
  --name giga-mst-superset-tg \
  --protocol HTTP \
  --port 8088 \
  --target-type ip \
  --vpc-id <vpc-id> \
  --health-check-path /health

# Create ALB
aws elbv2 create-load-balancer \
  --name giga-mst-alb \
  --subnets <subnet-1> <subnet-2> \
  --security-groups <alb-sg-id>

# Create HTTPS listener (requires ACM certificate)
aws elbv2 create-listener \
  --load-balancer-arn <alb-arn> \
  --protocol HTTPS \
  --port 443 \
  --certificates CertificateArn=<acm-cert-arn> \
  --default-actions Type=forward,TargetGroupArn=<target-group-arn>
```

### Request SSL Certificate

```bash
aws acm request-certificate \
  --domain-name mst.your-domain.com \
  --validation-method DNS
```

---

## Monitoring & Logging

### CloudWatch Alarms

```bash
# CPU utilization alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "giga-mst-cpu-high" \
  --metric-name CPUUtilization \
  --namespace AWS/ECS \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=ClusterName,Value=giga-mst-cluster Name=ServiceName,Value=superset \
  --evaluation-periods 2 \
  --alarm-actions <sns-topic-arn>

# Memory utilization alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "giga-mst-memory-high" \
  --metric-name MemoryUtilization \
  --namespace AWS/ECS \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=ClusterName,Value=giga-mst-cluster Name=ServiceName,Value=superset \
  --evaluation-periods 2 \
  --alarm-actions <sns-topic-arn>
```

### Log Insights Query Examples

```sql
-- View Superset errors
fields @timestamp, @message
| filter @logStream like /superset/
| filter @message like /ERROR/
| sort @timestamp desc
| limit 100

-- Celery task failures
fields @timestamp, @message
| filter @logStream like /celery/
| filter @message like /Task.*failed/
| sort @timestamp desc
| limit 50
```

---

## Cost Estimation

### ECS Fargate (Monthly Estimate)

| Resource | Configuration | Est. Monthly Cost |
|----------|---------------|-------------------|
| Superset (2 tasks) | 1 vCPU, 2GB | ~$60 |
| Celery Worker (2 tasks) | 1 vCPU, 2GB | ~$60 |
| Celery Beat (1 task) | 0.25 vCPU, 0.5GB | ~$10 |
| RDS Metadata | db.t3.small | ~$25 |
| RDS Data (PostGIS) | db.t3.medium | ~$50 |
| ElastiCache Redis | cache.t3.micro | ~$15 |
| ALB | Standard | ~$20 |
| Data Transfer | ~50GB | ~$5 |
| **Total** | | **~$245/month** |

### EC2 Option (Monthly Estimate)

| Resource | Configuration | Est. Monthly Cost |
|----------|---------------|-------------------|
| EC2 Instance | t3.medium | ~$30 |
| EBS Storage | 50GB gp3 | ~$5 |
| Elastic IP | 1 | ~$4 |
| Data Transfer | ~50GB | ~$5 |
| **Total** | | **~$44/month** |

---

## Security Checklist

- [ ] Use private subnets for databases and Redis
- [ ] Configure security groups with least-privilege access
- [ ] Enable encryption at rest for RDS and ElastiCache
- [ ] Enable encryption in transit (TLS/SSL)
- [ ] Store all secrets in Secrets Manager
- [ ] Enable CloudTrail for API auditing
- [ ] Configure VPC flow logs
- [ ] Set up AWS WAF for the ALB
- [ ] Rotate secrets regularly
- [ ] Enable MFA for AWS console access
- [ ] Review IAM policies quarterly

---

## Troubleshooting

### Common Issues

**1. Task fails to start**
```bash
# Check task stopped reason
aws ecs describe-tasks --cluster giga-mst-cluster --tasks <task-id>
```

**2. Database connection issues**
- Verify security group allows traffic from ECS tasks
- Check RDS endpoint in environment variables
- Ensure RDS is in the same VPC

**3. Redis connection issues**
- Verify ElastiCache endpoint
- Check security group rules

**4. Celery tasks not executing**
- Check Celery worker logs in CloudWatch
- Verify Redis broker connectivity
- Ensure beat schedule is running

---

## CI/CD Pipeline (GitHub Actions)

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy to AWS ECS

on:
  push:
    branches: [main]

env:
  AWS_REGION: us-east-1
  ECR_REPOSITORY: giga-mst/superset
  ECS_CLUSTER: giga-mst-cluster
  ECS_SERVICE: superset

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build, tag, and push image to Amazon ECR
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
          docker tag $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG $ECR_REGISTRY/$ECR_REPOSITORY:latest
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:latest

      - name: Update ECS service
        run: |
          aws ecs update-service --cluster $ECS_CLUSTER --service $ECS_SERVICE --force-new-deployment
          aws ecs update-service --cluster $ECS_CLUSTER --service celery-worker --force-new-deployment
          aws ecs update-service --cluster $ECS_CLUSTER --service celery-beat --force-new-deployment
```

---

## Next Steps

1. Set up staging environment
2. Configure automated backups
3. Implement blue-green deployments
4. Set up disaster recovery procedures
5. Create runbooks for common operations
