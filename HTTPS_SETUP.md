# HTTPS Setup - Giga MST Superset

## ✅ What Was Configured

### 1. CloudFront Distribution
- **CloudFront URL**: `https://d5cdy1ilvnp8r.cloudfront.net`
- **Distribution ID**: `E23UBHRH5KRW8K`
- **Status**: Deploying (takes 10-15 minutes)
- **SSL Certificate**: AWS-managed CloudFront certificate (free, auto-renewed)
- **Features**:
  - Automatic HTTP to HTTPS redirect
  - Static content caching (`/static/*` cached for 24 hours)
  - Dynamic content passed through with no caching
  - All HTTP methods supported (GET, POST, PUT, PATCH, DELETE)

### 2. ECS Task Definitions Updated
All services updated with new environment variables:

#### Superset Service (revision 5)
- `SUPERSET_PUBLIC_URL=https://d5cdy1ilvnp8r.cloudfront.net`
- `WEBDRIVER_BASEURL=http://giga-mst-alb-1502440895.eu-west-1.elb.amazonaws.com`
- `SUPERSET_WEBSERVER_PROTOCOL=https`
- `SESSION_COOKIE_SECURE=true`

#### Celery Worker (revision 4) & Celery Beat (revision 4)
- Same environment variables as above
- Ensures alerts/reports use HTTPS URLs

### 3. Superset Configuration
Updated `superset_config.py`:
- Added `SUPERSET_WEBSERVER_PROTOCOL` configuration
- Secure cookies enabled when `SESSION_COOKIE_SECURE=true`

## 🔐 Security Features Enabled

1. **End-to-End Encryption**:
   - User → CloudFront: HTTPS (TLS 1.2+)
   - CloudFront → ALB: HTTP (within AWS VPC, secured by security groups)
   - ALB → ECS: HTTP (internal VPC traffic)

2. **Secure Cookies**:
   - Session cookies marked as `Secure` (only sent over HTTPS)
   - `HttpOnly` flag prevents JavaScript access
   - `SameSite=Lax` for CSRF protection

3. **Content Security Policy**:
   - Already configured in `superset_config.py` via `TALISMAN_CONFIG`

## 📋 Access Your Superset Instance

### Current Status
- **CloudFront**: Deploying (check status below)
- **ECS Services**: All running with new configurations
- **Old HTTP URL**: Still works at `http://giga-mst-alb-1502440895.eu-west-1.elb.amazonaws.com`

### Check CloudFront Deployment Status
```bash
aws cloudfront get-distribution --id E23UBHRH5KRW8K --query "Distribution.Status" --output text
```

When status shows `Deployed`, access your instance at:
```
https://d5cdy1ilvnp8r.cloudfront.net
```

## 🔄 Switching to a Custom Domain Later

When you get your ITU domain (e.g., `giga.mst.itu` or subdomain under `cpp.itu.int`):

### Step 1: Request ACM Certificate
```bash
aws acm request-certificate \
  --region us-east-1 \
  --domain-name your-domain.itu.int \
  --validation-method DNS
```

**Note**: CloudFront certificates must be in `us-east-1` region

### Step 2: Validate Certificate
Follow AWS Console instructions to add DNS validation records to Route53

### Step 3: Update CloudFront Distribution
```bash
aws cloudfront get-distribution-config --id E23UBHRH5KRW8K > /tmp/cf-config.json

# Edit /tmp/cf-config.json to add:
# - "Aliases": ["your-domain.itu.int"]
# - "ViewerCertificate": { "ACMCertificateArn": "arn:...", ... }

aws cloudfront update-distribution \
  --id E23UBHRH5KRW8K \
  --if-match <ETag-from-get-command> \
  --distribution-config file:///tmp/cf-config-updated.json
```

### Step 4: Add Route53 DNS Record
```bash
aws route53 change-resource-record-sets \
  --hosted-zone-id Z00424093EXI12T9Z7DUL \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "your-domain.cpp.itu.int",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [{"Value": "d5cdy1ilvnp8r.cloudfront.net"}]
      }
    }]
  }'
```

### Step 5: Update ECS Environment Variables
```bash
# Update SUPERSET_PUBLIC_URL to your custom domain
aws ecs register-task-definition --cli-input-json file://updated-task-def.json
aws ecs update-service --cluster giga-mst-cluster --service giga-mst-superset --task-definition <new-revision>
```

## 🧪 Testing

### Test HTTPS Connection
```bash
curl -I https://d5cdy1ilvnp8r.cloudfront.net
```

Expected response:
```
HTTP/2 200
x-cache: Miss from cloudfront
```

### Test HTTP Redirect
```bash
curl -I http://d5cdy1ilvnp8r.cloudfront.net
```

Expected: Redirect to HTTPS

### Test Superset Health
```bash
curl https://d5cdy1ilvnp8r.cloudfront.net/health
```

Expected: `{"status": "ok"}`

## 🛠 Troubleshooting

### CloudFront 502 Bad Gateway
- Check ALB target group health: `aws elbv2 describe-target-health --target-group-arn <arn>`
- Check ECS task logs: `aws logs tail /ecs/giga-mst --follow`

### Session/Login Issues
- Clear browser cookies
- Check ECS logs for session errors
- Verify `SESSION_COOKIE_SECURE=true` is set

### Alerts/Reports Not Working
- Check Celery worker logs for screenshot errors
- Verify `WEBDRIVER_BASEURL` points to ALB (not CloudFront)
- Ensure Celery workers have network access to ALB

## 📊 Monitoring

### CloudFront Metrics (CloudWatch)
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/CloudFront \
  --metric-name Requests \
  --dimensions Name=DistributionId,Value=E23UBHRH5KRW8K \
  --start-time 2026-01-31T00:00:00Z \
  --end-time 2026-01-31T23:59:59Z \
  --period 3600 \
  --statistics Sum
```

### ECS Service Status
```bash
aws ecs describe-services \
  --cluster giga-mst-cluster \
  --services giga-mst-superset \
  --query "services[0].{Status:status,Running:runningCount,Desired:desiredCount}"
```

## 💰 Cost Estimate

- **CloudFront**: ~$0.085/GB data transfer out + $0.01/10,000 requests
- **ECS/Fargate**: No change (already running)
- **ACM Certificate**: Free (AWS-managed)

Estimated monthly cost for moderate traffic (10GB, 100K requests): ~$2-3 USD

## 📝 Files Created/Modified

### Modified
- `superset_config.py` - Added HTTPS protocol configuration

### Created
- `cloudfront-config.json` - CloudFront distribution configuration
- `update-celery-tasks.py` - Script to update Celery task definitions
- `HTTPS_SETUP.md` - This file

### Generated (temporary)
- `/tmp/superset-task-def.json` - Original Superset task definition
- `/tmp/superset-task-def-new.json` - Updated Superset task definition
- `/tmp/giga-mst-celery-worker-new.json` - Updated worker task definition
- `/tmp/giga-mst-celery-beat-new.json` - Updated beat task definition

## 🎉 Next Steps

1. **Wait for CloudFront deployment** (~10-15 minutes)
2. **Test the HTTPS URL**: `https://d5cdy1ilvnp8r.cloudfront.net`
3. **Update any bookmarks** or documentation with new URL
4. **Monitor CloudWatch** for any errors
5. **Plan custom domain migration** when ITU domain is ready
