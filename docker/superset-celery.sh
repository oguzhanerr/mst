#!/bin/bash

set -eo pipefail

# Verify that the script has exactly one argument
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 {worker|beat}"
    exit 1
fi

TYPE="$1"
echo "Starting celery $TYPE..."

case "$TYPE" in
    worker)
        exec celery --app=superset.tasks.celery_app:app worker --pool=prefork -O fair -c 4 --loglevel=info
        ;;
    beat)
        exec celery --app=superset.tasks.celery_app:app beat \
            --loglevel=info \
            --schedule=/app/celerybeat/celerybeat-schedule
        ;;
    *)
        echo "Unknown argument: $TYPE"
        exit 1
        ;;
esac