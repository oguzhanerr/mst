#!/bin/bash

# Exit on error
set -e

# Create Admin user
superset fab create-admin \
    --username "$SUPERSET_USER" \
    --firstname Superset \
    --lastname Admin \
    --email example@admin.com \
    --password "$SUPERSET_PASSWORD"

# Upgrade the Superset database
superset db upgrade

# Initialize Superset (roles, permissions, etc.)
superset init

# Load example data and dashboards
superset load_examples