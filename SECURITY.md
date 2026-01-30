# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Reporting a Vulnerability

We take security seriously. If you discover a security vulnerability, please report it responsibly.

### How to Report

1. **Do NOT** open a public GitHub issue for security vulnerabilities
2. Email the maintainers directly with:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Any suggested fixes (optional)

### What to Expect

- **Acknowledgment**: Within 48 hours
- **Initial Assessment**: Within 1 week
- **Resolution Timeline**: Depends on severity
  - Critical: 24-48 hours
  - High: 1 week
  - Medium: 2-4 weeks
  - Low: Next release

### Security Best Practices for Users

1. **Never commit secrets** to the repository
   - Use environment templates and `.gitignore`
   - Store secrets in AWS Secrets Manager for production

2. **Keep dependencies updated**
   - Regularly rebuild Docker images
   - Monitor for CVEs in base images

3. **Use HTTPS in production**
   - Configure SSL/TLS via load balancer
   - Enable `force_https` in Superset config

4. **Restrict database access**
   - Use private subnets for RDS
   - Configure security groups properly

5. **Rotate credentials regularly**
   - Database passwords
   - Superset secret key
   - API keys

## Security Features

This project includes several security measures:

- Environment variables for secrets (not hardcoded)
- `.gitignore` excludes sensitive files
- Content Security Policy (CSP) headers via Talisman
- Redis-backed rate limiting
- Separate metadata and data databases

## Acknowledgments

We appreciate responsible disclosure and will acknowledge security researchers who report valid vulnerabilities (with their permission).
