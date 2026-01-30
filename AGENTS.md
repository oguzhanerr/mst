# AGENTS.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

This is a Dockerized Apache Superset deployment for the **Giga Mobile Simulation Tool** (MST). It visualizes Rwanda school connectivity and cell tower coverage data using PostGIS for geospatial queries.

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

- **superset**: Main web application (port 8088), runs via Gunicorn with gevent workers
- **celery_worker/beat**: Handles async SQL queries, scheduled alerts/reports using Firefox+Geckodriver for screenshots
- **database**: PostGIS with pre-loaded Rwanda data (schools, cell towers, coverage polygons)
- **metadata_db**: Superset's internal metadata storage
- **redis**: Celery broker and result backend, also powers all caching layers

## Key Files

- `superset_config.py` - All Superset configuration (feature flags, caching, Celery, SMTP, webdriver settings)
- `compose.yaml` - Production stack with all services
- `compose.init.yaml` - One-time initialization (creates admin user, runs migrations, loads examples)
- `database/init.sql` - Schema and data loading for PostGIS database
- `env/` - Environment files: `.superset.env`, `.database.env`, `.metadata.env`

## Commands

### First-time setup (initialize Superset)
```bash
docker compose -f compose.init.yaml up --build
```

### Start the full stack
```bash
docker compose up --build -d
```

### View logs
```bash
docker compose logs -f superset
docker compose logs -f celery_worker
```

### Rebuild after config changes
```bash
docker compose up --build -d superset celery_worker celery_beat
```

### Access database directly
```bash
docker exec -it mst_database psql -U <user> -d <dbname>
```

### Stop all services
```bash
docker compose down
```

### Reset volumes (destructive)
```bash
docker compose down -v
```

## Data Model

The PostGIS database contains:
- `school` - School locations with connectivity attributes (giga_id_school, lat/lon, 2G/3G/4G coverage flags)
- `celltower` - Cell tower positions with radio type
- `coverage` - Coverage polygons as WKT geometries
- `coverage_geojson` - View that converts coverage to GeoJSON for Superset map visualizations

## Configuration Notes

- Custom branding assets in `docker/src/img/` are copied to `/app/superset/static/assets/images/custom_logos/`
- Feature flags in `superset_config.py` enable alerts/reports, drill-by, and template processing
- Celery beat schedule runs `reports.scheduler` every minute for alert checking
- All caches (results, filters, explore) use Redis with 24-hour TTL
