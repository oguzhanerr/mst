# Giga Mobile Simulation Tool (MST)

A Dockerized Apache Superset deployment for visualizing Rwanda school connectivity and cell tower coverage data using PostGIS for geospatial queries.

![Superset](https://img.shields.io/badge/Apache%20Superset-4.0-blue)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED)
![PostGIS](https://img.shields.io/badge/PostGIS-3.4-green)
![License](https://img.shields.io/badge/License-MIT-yellow)

## Overview

The Giga Mobile Simulation Tool provides interactive dashboards and map visualizations for analyzing:
- School locations with connectivity attributes
- Cell tower positions and radio types (2G/3G/4G)
- Coverage polygons and connectivity gaps

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Docker Compose Stack                      │
├──────────────┬──────────────┬──────────────┬────────────────┤
│   superset   │ celery_worker│ celery_beat  │   database     │
│   (app)      │ (async tasks)│ (scheduler)  │   (PostGIS)    │
├──────────────┴──────────────┴──────────────┼────────────────┤
│              metadata_db (Postgres 16)     │     redis      │
└────────────────────────────────────────────┴────────────────┘
```

## Quick Start

### Prerequisites

- Docker & Docker Compose
- Git

### 1. Clone the Repository

```bash
git clone https://github.com/oguzhanerr/mst.git
cd mst
```

### 2. Configure Environment Variables

Copy the template files and fill in your values:

```bash
cp env/.superset.env.template env/.superset.env
cp env/.database.env.template env/.database.env
cp env/.metadata.env.template env/.metadata.env
```

Edit each file with your configuration (passwords, API keys, etc.)

### 3. Initialize Superset (First Time Only)

```bash
docker compose -f compose.init.yaml up --build
```

This will:
- Create the admin user
- Run database migrations
- Load example dashboards

### 4. Start the Application

```bash
docker compose up --build -d
```

Access Superset at: **http://localhost:8088**

## Services

| Service | Port | Description |
|---------|------|-------------|
| superset | 8088 | Main web application |
| celery_worker | - | Async task processing |
| celery_beat | - | Scheduled tasks (alerts/reports) |
| database | 5434 | PostGIS with Rwanda data |
| metadata_db | 5433 | Superset metadata storage |
| redis | 6379 | Caching & Celery broker |

## Data Model

The PostGIS database contains:

- **school** - School locations with connectivity attributes (giga_id_school, lat/lon, 2G/3G/4G coverage flags)
- **celltower** - Cell tower positions with radio type
- **coverage** - Coverage polygons as WKT geometries
- **coverage_geojson** - View that converts coverage to GeoJSON for map visualizations

## Common Commands

```bash
# View logs
docker compose logs -f superset
docker compose logs -f celery_worker

# Rebuild after config changes
docker compose up --build -d superset celery_worker celery_beat

# Access database
docker exec -it mst_database psql -U postgres -d mst

# Stop all services
docker compose down

# Reset everything (destructive)
docker compose down -v
```

## AWS Deployment

For production deployment on AWS, see the [AWS Deployment Guide](docs/AWS_DEPLOYMENT.md).

Quick deploy:
```bash
./scripts/deploy-aws.sh full
```

## Project Structure

```
mst/
├── compose.yaml              # Production Docker Compose
├── compose.init.yaml         # Initialization compose file
├── Dockerfile                # Superset image build
├── superset_config.py        # Superset configuration
├── requirements.txt          # Python dependencies
├── database/
│   ├── Dockerfile            # PostGIS image build
│   ├── init.sql              # Schema and data loading
│   └── *.csv                 # Rwanda data files
├── docker/
│   ├── superset-entrypoint.sh
│   ├── superset-init.sh
│   ├── superset-celery.sh
│   └── src/img/              # Custom branding assets
├── env/
│   ├── .superset.env.template
│   ├── .database.env.template
│   └── .metadata.env.template
├── docs/
│   └── AWS_DEPLOYMENT.md     # AWS deployment guide
├── cloudformation/
│   └── vpc.yaml              # AWS infrastructure template
└── scripts/
    └── deploy-aws.sh         # AWS deployment script
```

## Features

- **Map Visualizations** - Interactive maps with school and tower locations
- **Coverage Analysis** - 2G/3G/4G coverage polygon overlays
- **Alerts & Reports** - Scheduled email reports with dashboard screenshots
- **Custom Branding** - Giga-branded UI with custom logos
- **Caching** - Redis-powered caching for fast dashboard loads

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Apache Superset](https://superset.apache.org/)
- [Giga Initiative](https://giga.global/)
- [PostGIS](https://postgis.net/)
