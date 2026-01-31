#!/bin/bash
# Local Deployment Initialization Script
# This script sets up Superset with all MST assets for local development

set -e

SUPERSET_BIN="/app/.venv/bin/superset"

echo "============================================"
echo "MST Superset Local Deployment Initialization"
echo "============================================"

# Wait for metadata database to be ready
echo "[1/8] Waiting for metadata database..."
while ! pg_isready -h ${SUPERSET_META_HOST:-metadata_db} -p ${SUPERSET_META_PORT:-5432} -U ${SUPERSET_META_USER:-superset} -q; do
    sleep 2
done
echo "      ✓ Metadata database is ready"

# Wait for MST data database to be ready
echo "[2/8] Waiting for MST data database..."
while ! pg_isready -h database -p 5432 -U ${POSTGRES_USER:-postgres} -q; do
    sleep 2
done
echo "      ✓ MST data database is ready"

# Run database migrations
echo "[3/8] Running database migrations..."
$SUPERSET_BIN db upgrade
echo "      ✓ Migrations complete"

# Initialize Superset (roles, permissions)
echo "[4/8] Initializing Superset..."
$SUPERSET_BIN init
echo "      ✓ Superset initialized"

# Create admin user
echo "[5/8] Creating admin user..."
$SUPERSET_BIN fab create-admin \
    --username "${SUPERSET_USER:-admin}" \
    --firstname Superset \
    --lastname Admin \
    --email example@admin.com \
    --password "${SUPERSET_PASSWORD:-admin}" || true

$SUPERSET_BIN fab reset-password \
    --username "${SUPERSET_USER:-admin}" \
    --password "${SUPERSET_PASSWORD:-admin}"
echo "      ✓ Admin user created"

# Create viewer user
echo "[6/8] Creating viewer user..."
$SUPERSET_BIN fab create-user \
    --username "${SUPERSET_VIEWER_USER:-mst_viewer}" \
    --firstname MST \
    --lastname Viewer \
    --email viewer@itu.int \
    --password "${SUPERSET_VIEWER_PASSWORD:-viewer}" \
    --role Gamma || true

$SUPERSET_BIN fab reset-password \
    --username "${SUPERSET_VIEWER_USER:-mst_viewer}" \
    --password "${SUPERSET_VIEWER_PASSWORD:-viewer}"
echo "      ✓ Viewer user created"

# Create PostgreSQL database connection
echo "[7/8] Setting up database connection..."
$SUPERSET_BIN set-database-uri \
    --database_name "PostgreSQL" \
    --uri "postgresql://${POSTGRES_USER:-postgres}:${POSTGRES_PASSWORD:-postgres}@database:5432/${POSTGRES_DB:-mst}"
echo "      ✓ Database connection configured"

# Import dashboards and assets
echo "[8/8] Importing MST assets..."

# Import dashboards from the export directory
if [ -d "/app/examples/dashboard_export" ]; then
    echo "      Importing dashboards..."
    $SUPERSET_BIN import-directory /app/examples/dashboard_export || echo "      Warning: Some dashboard imports may have failed"
fi

# Import saved queries
if [ -d "/app/examples/aws_export/saved_queries" ]; then
    echo "      Importing saved queries..."
    python3 << 'PYEOF'
import glob
import datetime as dt
import os

from superset.app import create_app
from superset.extensions import db
from superset import security_manager
from superset.models.core import Database
from superset.models.sql_lab import SavedQuery

app = create_app()
with app.app_context():
    db_obj = db.session.query(Database).filter(Database.database_name == "PostgreSQL").first()
    if not db_obj:
        print("      Warning: PostgreSQL database not found, skipping saved queries")
        exit(0)
    
    creator = security_manager.find_user(username=os.getenv("SUPERSET_USER", "admin"))
    
    sql_files = sorted(glob.glob("/app/examples/aws_export/saved_queries/*.sql"))
    
    for fp in sql_files:
        with open(fp) as f:
            content = f.read()
        
        lines = content.split('\n')
        label = lines[0].replace('-- ', '').strip()
        sql = '\n'.join([l for l in lines if not l.startswith('--')]).strip()
        
        # Check if already exists
        existing = db.session.query(SavedQuery).filter(SavedQuery.label == label).first()
        if existing:
            continue
        
        sq = SavedQuery(
            label=label,
            sql=sql,
            db_id=db_obj.id,
            schema='public',
            user_id=creator.id if creator else None,
            created_by_fk=creator.id if creator else None,
            changed_by_fk=creator.id if creator else None,
        )
        db.session.add(sq)
    
    db.session.commit()
    print(f"      Imported {len(sql_files)} saved queries")
PYEOF
fi

echo ""
echo "============================================"
echo "Local deployment initialization complete!"
echo "============================================"
echo ""
echo "Access Superset at: http://localhost:8088"
echo ""
echo "Users:"
echo "  Admin:  ${SUPERSET_USER:-admin} / ${SUPERSET_PASSWORD:-admin}"
echo "  Viewer: ${SUPERSET_VIEWER_USER:-mst_viewer} / ${SUPERSET_VIEWER_PASSWORD:-viewer}"
echo ""
