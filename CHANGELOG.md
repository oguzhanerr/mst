# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- AWS deployment documentation and CloudFormation templates
- GitHub Actions CI/CD pipeline for automated deployments
- Deployment helper script (`scripts/deploy-aws.sh`)
- Environment variable templates for secure configuration
- Project README with setup instructions
- Contributing guidelines
- MIT License

## [1.0.0] - 2026-01-30

### Added
- Initial release of Giga Mobile Simulation Tool
- Dockerized Apache Superset deployment
- PostGIS database with Rwanda school and cell tower data
- Celery workers for async task processing
- Celery beat for scheduled alerts and reports
- Redis caching for improved performance
- Custom Giga branding and logos
- Map visualizations with Mapbox integration
- Coverage polygon overlays (2G/3G/4G)
- Email alerts and scheduled reports with Firefox/Geckodriver

### Data
- Rwanda school locations with connectivity attributes
- Cell tower positions with radio types
- Coverage polygons in WKT format
- GeoJSON view for Superset map visualizations
