#!/bin/bash
set -euo pipefail

PORT="${SUPERSET_PORT:-8088}"
WORKERS="${GUNICORN_WORKERS:-4}"
TIMEOUT="${GUNICORN_TIMEOUT:-120}"


echo "Starting Superset webserver on port $PORT..."
exec gunicorn \
    --bind "0.0.0.0:$PORT" \
    --workers "$WORKERS" \
    --worker-class gevent \
    --timeout "$TIMEOUT" \
    "${FLASK_APP}"
