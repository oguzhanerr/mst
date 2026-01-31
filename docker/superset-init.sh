#!/bin/bash

# Exit on error
set -e

SUPerset_BIN="/app/.venv/bin/superset"

# Create Admin user (if missing) and always reset password.
# Some Superset versions print "User already exists" but still exit 0, so we can't rely on `||`.
$SUPerset_BIN fab create-admin \
    --username "$SUPERSET_USER" \
    --firstname Superset \
    --lastname Admin \
    --email example@admin.com \
    --password "$SUPERSET_PASSWORD" \
  || true

$SUPerset_BIN fab reset-password \
    --username "$SUPERSET_USER" \
    --password "$SUPERSET_PASSWORD"

# Upgrade the Superset database
$SUPerset_BIN db upgrade

# Initialize Superset (roles, permissions, etc.)
$SUPerset_BIN init

# Optionally import the MST dashboards/charts/datasets packaged in the image.
# This is off by default so local compose init doesn't unexpectedly try to wire AWS RDS.
if [ "${SUPERSET_IMPORT_MST_ASSETS:-0}" = "1" ]; then
    MST_MARKER="/app/superset_home/.mst_assets_imported"
    if [ -f "$MST_MARKER" ]; then
        echo "[INFO] MST assets already imported ($MST_MARKER exists); skipping."
    else
        echo "[INFO] Importing MST Superset assets..."
        $SUPerset_BIN import-directory /app/examples/dashboard_export
        touch "$MST_MARKER"
    fi

    # Ensure the imported DB connection points to the *actual* Postgres/PostGIS endpoint.
    # This fixes the common AWS issue where imports reference docker-compose hostnames like `database`.
    DB_NAME="${SUPERSET_MST_DB_NAME:-PostgreSQL}"
    DB_USER="${POSTGIS_USER:-${DATABASE_USER}}"
    DB_PASS="${POSTGIS_PASSWORD:-${DATABASE_PASSWORD}}"
    DB_HOST="${POSTGIS_HOST:-database}"
    DB_PORT="${POSTGIS_PORT:-5432}"
    DB_DBNAME="${POSTGIS_DB:-mst}"

    echo "[INFO] Setting Superset DB connection '$DB_NAME' to ${DB_HOST}:${DB_PORT}/${DB_DBNAME}"
    $SUPerset_BIN set-database-uri \
      --database_name "$DB_NAME" \
      --uri "postgresql://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_DBNAME}"

    # Import MST example SQL queries as Saved Queries in SQL Lab (visible for users with SQL Lab access).
    # This is idempotent: it upserts by (label, database_id).
    if [ "${SUPERSET_IMPORT_MST_QUERIES:-1}" = "1" ]; then
        echo "[INFO] Importing MST example SQL queries into Saved Queries..."
        /app/.venv/bin/python - <<'PY'
import glob
import os
from pathlib import Path
import datetime as dt

from superset.app import create_app
from superset.extensions import db

app = create_app()
app.app_context().push()

from superset import security_manager
from superset.models.core import Database

try:
    from sqlalchemy import inspect, text
except Exception:  # pragma: no cover
    from sqlalchemy import text  # type: ignore
    inspect = None  # type: ignore

DB_NAME = os.getenv("SUPERSET_MST_DB_NAME", "PostgreSQL")
CREATOR_USERNAME = os.getenv("SUPERSET_USER", "admin")
DEFAULT_SCHEMA = os.getenv("POSTGIS_SCHEMA", "public")

# Find the Superset DB connection by name
q = db.session.query(Database)
db_obj = q.filter(Database.database_name == DB_NAME).one_or_none()
if db_obj is None:
    # fallback for older versions
    db_obj = q.filter(getattr(Database, "database_name", Database.database_name) == DB_NAME).one_or_none()
if db_obj is None:
    raise SystemExit(f"Database connection not found in Superset: {DB_NAME!r}")

creator = security_manager.find_user(username=CREATOR_USERNAME)
creator_id = getattr(creator, "id", None) if creator else None

# Determine saved_query columns dynamically (works across Superset versions)
cols = None
if inspect is not None:
    try:
        cols = {c["name"] for c in inspect(db.engine).get_columns("saved_query")}
    except Exception:
        cols = None

# Fallback set (common across versions)
# Note: created_on/changed_on are important for the Saved Queries API (it computes "age").
if not cols:
    cols = {
        "label",
        "description",
        "sql",
        "db_id",
        "schema",
        "user_id",
        "created_by_fk",
        "changed_by_fk",
        "created_on",
        "changed_on",
    }

# Load .sql files bundled in the image
sql_files = sorted(glob.glob("/app/examples/*.sql"))
if not sql_files:
    print("[WARN] No /app/examples/*.sql files found; skipping saved queries import")
    raise SystemExit(0)

# Human-friendly labels
LABELS = {
    "alert_queries.sql": "Example: Alert Queries",
    "celltower_analysis.sql": "Example: Cell Tower Analysis",
    "coverage_analysis.sql": "Example: 4G Coverage Analysis",
    "dashboard_kpis.sql": "Example: Dashboard KPIs",
    "school_analysis.sql": "Example: School Analysis",
    "snowflake_alerts_demo.sql": "Example: Snowflake Alerts Demo",
}

upserts = 0
now = dt.datetime.utcnow()
for fp in sql_files:
    p = Path(fp)
    label = LABELS.get(p.name, f"Example: {p.stem.replace('_', ' ').title()}")
    sql = p.read_text(encoding="utf-8")

    # Strip accidental control chars (we hit this once with MAPBOX)
    sql = "".join(ch for ch in sql if ord(ch) >= 32 or ch in "\n\t\r")

    # upsert by (label, database)
    existing = db.session.execute(
        text("SELECT id FROM saved_query WHERE label=:label AND db_id=:db_id"),
        {"label": label, "db_id": db_obj.id},
    ).fetchone()

    if existing:
        set_clauses = ["sql=:sql", "description=:desc"]
        params = {
            "id": existing[0],
            "sql": sql,
            "desc": f"MST example query from {p.name}",
        }
        if "changed_by_fk" in cols:
            set_clauses.append("changed_by_fk=:changed_by")
            params["changed_by"] = creator_id
        if "changed_on" in cols:
            set_clauses.append("changed_on=:changed_on")
            params["changed_on"] = now

        db.session.execute(
            text(f"UPDATE saved_query SET {', '.join(set_clauses)} WHERE id=:id"),
            params,
        )
    else:
        row = {}
        if "label" in cols:
            row["label"] = label
        if "description" in cols:
            row["description"] = f"MST example query from {p.name}"
        if "sql" in cols:
            row["sql"] = sql
        if "db_id" in cols:
            row["db_id"] = db_obj.id
        if "schema" in cols:
            row["schema"] = DEFAULT_SCHEMA
        if "user_id" in cols:
            row["user_id"] = creator_id
        if "created_by_fk" in cols:
            row["created_by_fk"] = creator_id
        if "changed_by_fk" in cols:
            row["changed_by_fk"] = creator_id
        if "created_on" in cols:
            row["created_on"] = now
        if "changed_on" in cols:
            row["changed_on"] = now

        keys = ",".join(row.keys())
        binds = ",".join(f":{k}" for k in row.keys())
        db.session.execute(text(f"INSERT INTO saved_query ({keys}) VALUES ({binds})"), row)

    upserts += 1

db.session.commit()
print(f"[INFO] Saved queries upserted: {upserts}")
PY
    else
        echo "[INFO] SUPERSET_IMPORT_MST_QUERIES not set; skipping saved queries import."
    fi
else
    echo "[INFO] SUPERSET_IMPORT_MST_ASSETS not set; skipping MST asset import."
fi

# Load example data and dashboards
# - Skip by default (useful for AWS/prod)
# - For local dev, set SUPERSET_LOAD_EXAMPLES=1
# - When /app/superset_home is persistent (docker volume), we write a marker so it only runs once.
MARKER_FILE="/app/superset_home/.examples_loaded"
if [ "${SUPERSET_LOAD_EXAMPLES:-}" = "1" ]; then
    if [ -f "$MARKER_FILE" ]; then
        echo "[INFO] Superset examples already loaded ($MARKER_FILE exists); skipping."
    else
        echo "[INFO] Loading Superset examples (first time)..."
        $SUPerset_BIN load_examples
        touch "$MARKER_FILE"
    fi
else
    echo "[INFO] SUPERSET_LOAD_EXAMPLES not set; skipping example data load."
fi
