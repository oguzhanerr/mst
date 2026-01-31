# Local Deployment Guide

This guide explains how to deploy the MST Superset instance locally for development and testing.

## Quick Start

### First-time Setup

```bash
# Clone the repository and switch to local-deployment branch
git clone https://github.com/oguzhanerr/mst.git
cd mst
git checkout local-deployment

# Start the full stack (builds images and initializes everything)
docker compose -f compose.local.yaml up --build
```

The initialization process will:
1. Start PostgreSQL databases (metadata + MST data)
2. Start Redis
3. Run database migrations
4. Create admin and viewer users
5. Set up database connections
6. Import all dashboards, datasets, and saved queries

**First startup takes 3-5 minutes.** Wait until you see:
```
============================================
Local deployment initialization complete!
============================================
```

### Access Superset

- **URL:** http://localhost:8088
- **Admin:** `admin` / `Giga@Mst2026!`
- **Viewer:** `mst_viewer` / `MstViewer2026!`

### Subsequent Starts

```bash
# Start in detached mode
docker compose -f compose.local.yaml up -d

# View logs
docker compose -f compose.local.yaml logs -f superset

# Stop all services
docker compose -f compose.local.yaml down
```

## What's Included

| Component | Description |
|-----------|-------------|
| **12 Dashboards** | Including Mobile Simulation Tool |
| **29 Datasets** | School, celltower, coverage data |
| **6 Saved Queries** | Example SQL queries for analysis |
| **2 Users** | Admin and Viewer roles |

## Services

| Service | Port | Description |
|---------|------|-------------|
| superset | 8088 | Main web application |
| celery_worker | - | Async task processing |
| celery_beat | - | Scheduled tasks |
| metadata_db | 5433 | Superset metadata (PostgreSQL) |
| database | 5434 | MST data (PostGIS) |
| redis | 6379 | Cache & Celery broker |

## Customization

### Change Credentials

Edit the environment variables in `compose.local.yaml`:

```yaml
x-superset-env: &superset-env
  SUPERSET_USER: admin
  SUPERSET_PASSWORD: YourNewPassword
  SUPERSET_VIEWER_USER: mst_viewer
  SUPERSET_VIEWER_PASSWORD: YourViewerPassword
```

### Reset Everything

```bash
# Stop and remove all containers AND volumes
docker compose -f compose.local.yaml down -v

# Start fresh
docker compose -f compose.local.yaml up --build
```

## Troubleshooting

### Container won't start

```bash
# Check logs
docker compose -f compose.local.yaml logs superset_init

# Check if databases are healthy
docker compose -f compose.local.yaml ps
```

### Database connection error

If dashboards show "DB Engine Error", the database connection may need to be reconfigured:

```bash
docker exec superset_app superset set-database-uri \
  --database_name "PostgreSQL" \
  --uri "postgresql://postgres:postgres@database:5432/mst"
```

### Port already in use

Change the port mappings in `compose.local.yaml`:

```yaml
ports:
  - "9088:8088"  # Change 8088 to 9088
```

## Differences from AWS Deployment

| Feature | Local | AWS |
|---------|-------|-----|
| Compose file | `compose.local.yaml` | `compose.yaml` |
| Database | Local PostGIS container | RDS |
| Redis | Local container | ElastiCache |
| SSL/HTTPS | No | Yes (CloudFront) |
| Scaling | Single instance | ECS with multiple tasks |
| Data persistence | Docker volumes | RDS/EBS |

## Development Workflow

1. Make changes to code/config
2. Rebuild: `docker compose -f compose.local.yaml up --build -d`
3. Test at http://localhost:8088
4. Commit changes
5. Deploy to AWS via GitHub Actions
