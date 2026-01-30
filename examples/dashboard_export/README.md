# Mobile Simulation Tool Dashboard Export

This folder contains the exported Mobile Simulation Tool dashboard with all its components.

## Contents

- **dashboards/** - Dashboard configuration (layout, tabs, filters)
- **charts/** - All chart definitions (11 charts)
- **datasets/** - Dataset configurations (4 datasets)
- **databases/** - Database connection template

## Charts Included

| Chart | Type | Description |
|-------|------|-------------|
| School Coverage Map | deck_scatter | Interactive map of schools with 4G coverage |
| Connectivity Distribution | pie | Distribution of connectivity types |
| Electricity Availability | pie | Schools with/without electricity |
| Cell Tower Map | deck_scatter | Map of cell towers by radio type |
| Tower Distribution by Type | pie | GSM/UMTS/LTE tower breakdown |
| 4G Coverage Polygons | deck_geojson | Coverage area visualization |
| KPI: Total Schools | big_number | Total school count |
| KPI: 4G Coverage Rate | big_number | Percentage with 4G |
| KPI: Schools No Coverage | big_number | Schools without coverage |
| KPI: Total Towers | big_number | Total cell tower count |
| KPI: LTE Towers | big_number | 4G tower count |
| Dynamic Insights Summary | handlebars | Auto-generated summary text |

## Import Instructions

### Option 1: Via Superset UI

1. Go to **Settings** → **Import Dashboards**
2. Upload `mobile_simulation_tool_dashboard.zip`
3. Map the database connection to your PostgreSQL instance
4. Click **Import**

### Option 2: Via CLI

```bash
docker exec superset_app superset import-dashboards \
  -p /path/to/mobile_simulation_tool_dashboard.zip
```

### Option 3: Via API

```bash
TOKEN=$(curl -s -X POST "http://localhost:8088/api/v1/security/login" \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "YOUR_PASSWORD", "provider": "db"}' \
  | jq -r '.access_token')

curl -X POST "http://localhost:8088/api/v1/dashboard/import/" \
  -H "Authorization: Bearer $TOKEN" \
  -F "formData=@mobile_simulation_tool_dashboard.zip"
```

## Prerequisites

Before importing, ensure:

1. The PostgreSQL database connection exists with the same name (`PostgreSQL`)
2. The required tables exist:
   - `school` - School data with coverage fields
   - `celltower` - Cell tower locations
   - `coverage_geojson_fast` - Materialized view with GeoJSON polygons
   - `dashboard_summary_stats` - Virtual dataset for KPIs

## Post-Import Steps

1. Verify database connection points to your PostGIS instance
2. Refresh datasets to sync column metadata
3. Test each chart renders correctly
4. Publish the dashboard for viewer access
