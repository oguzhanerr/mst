# HTTPS Quick Reference

## 🌐 Your Superset is Now Live with HTTPS!

### Access URL
```
https://d5cdy1ilvnp8r.cloudfront.net
```

### Login Credentials
- **Admin User**: (check your AWS Secrets Manager or env/.superset.env)
- **Viewer User**: (check your AWS Secrets Manager or env/.superset.env)

## ✅ What's Secured

- ✅ HTTPS with AWS-managed SSL certificate
- ✅ Automatic HTTP → HTTPS redirect
- ✅ Secure session cookies
- ✅ All data encrypted in transit
- ✅ CDN caching for better performance

## 📊 Quick Health Check

```bash
# Test HTTPS connection
curl -I https://d5cdy1ilvnp8r.cloudfront.net/health

# Check CloudFront status
aws cloudfront get-distribution --id E23UBHRH5KRW8K --query "Distribution.Status"

# Check ECS services
aws ecs describe-services --cluster giga-mst-cluster --services giga-mst-superset --query "services[0].status"
```

## 🔧 Common Tasks

### Update Configuration
1. Edit `superset_config.py` locally
2. Rebuild Docker image: `docker build -t giga-mst/superset .`
3. Push to ECR: 
   ```bash
   aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin 905418185488.dkr.ecr.eu-west-1.amazonaws.com
   docker tag giga-mst/superset:latest 905418185488.dkr.ecr.eu-west-1.amazonaws.com/giga-mst/superset:latest
   docker push 905418185488.dkr.ecr.eu-west-1.amazonaws.com/giga-mst/superset:latest
   ```
4. Force ECS deployment:
   ```bash
   aws ecs update-service --cluster giga-mst-cluster --service giga-mst-superset --force-new-deployment
   ```

### View Logs
```bash
# Superset logs
aws logs tail /ecs/giga-mst --follow --filter-pattern superset

# Celery worker logs  
aws logs tail /ecs/giga-mst --follow --filter-pattern celery-worker
```

### Invalidate CloudFront Cache
```bash
aws cloudfront create-invalidation --distribution-id E23UBHRH5KRW8K --paths "/*"
```

## 🔄 Migrate to Custom Domain

When you have your ITU domain ready:

1. **Request certificate** (in us-east-1):
   ```bash
   aws acm request-certificate --region us-east-1 --domain-name your-domain.itu.int --validation-method DNS
   ```

2. **Update CloudFront** to use custom domain and certificate

3. **Add DNS record** pointing to `d5cdy1ilvnp8r.cloudfront.net`

4. **Update ECS env vars** to use new domain

See `HTTPS_SETUP.md` for detailed migration steps.

## 📞 Support

- CloudFront ID: `E23UBHRH5KRW8K`
- ECS Cluster: `giga-mst-cluster`
- Region: `eu-west-1`
- ALB: `giga-mst-alb-1502440895.eu-west-1.elb.amazonaws.com`

## 🔒 Security Notes

- Old HTTP URL still works (for internal testing)
- Session cookies only sent over HTTPS
- CloudFront has DDoS protection
- Keep AWS credentials secure
- Rotate Superset secret keys regularly
