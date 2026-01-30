#!/bin/bash
# Database Backup and Restore Script for Giga MST
# Usage: ./scripts/backup-db.sh [backup|restore|list] [options]

set -euo pipefail

# Configuration
BACKUP_DIR="${BACKUP_DIR:-./backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATA_CONTAINER="mst_database"
METADATA_CONTAINER="superset_metadata"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

backup_data_db() {
    local backup_file="$BACKUP_DIR/mst_data_${TIMESTAMP}.sql.gz"
    log_info "Backing up MST data database..."
    
    docker exec "$DATA_CONTAINER" pg_dump -U postgres -d mst | gzip > "$backup_file"
    
    log_info "Data backup saved to: $backup_file"
    echo "$backup_file"
}

backup_metadata_db() {
    local backup_file="$BACKUP_DIR/superset_metadata_${TIMESTAMP}.sql.gz"
    log_info "Backing up Superset metadata database..."
    
    docker exec "$METADATA_CONTAINER" pg_dump -U superset -d superset | gzip > "$backup_file"
    
    log_info "Metadata backup saved to: $backup_file"
    echo "$backup_file"
}

backup_all() {
    log_info "Starting full backup..."
    
    local data_file=$(backup_data_db)
    local metadata_file=$(backup_metadata_db)
    
    # Create a manifest
    local manifest="$BACKUP_DIR/backup_${TIMESTAMP}_manifest.txt"
    cat > "$manifest" << EOF
Backup Manifest
===============
Timestamp: $(date)
Data DB: $(basename "$data_file")
Metadata DB: $(basename "$metadata_file")

Restore commands:
  Data:     ./scripts/backup-db.sh restore data $(basename "$data_file")
  Metadata: ./scripts/backup-db.sh restore metadata $(basename "$metadata_file")
EOF
    
    log_info "Full backup complete!"
    log_info "Manifest: $manifest"
}

restore_data_db() {
    local backup_file="$1"
    
    if [[ ! -f "$BACKUP_DIR/$backup_file" ]]; then
        log_error "Backup file not found: $BACKUP_DIR/$backup_file"
        exit 1
    fi
    
    log_warn "This will REPLACE all data in the MST database!"
    read -p "Are you sure? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log_info "Restore cancelled."
        exit 0
    fi
    
    log_info "Restoring MST data database from $backup_file..."
    
    # Drop and recreate database
    docker exec "$DATA_CONTAINER" psql -U postgres -c "DROP DATABASE IF EXISTS mst;"
    docker exec "$DATA_CONTAINER" psql -U postgres -c "CREATE DATABASE mst;"
    
    # Restore
    gunzip -c "$BACKUP_DIR/$backup_file" | docker exec -i "$DATA_CONTAINER" psql -U postgres -d mst
    
    log_info "Data restore complete!"
}

restore_metadata_db() {
    local backup_file="$1"
    
    if [[ ! -f "$BACKUP_DIR/$backup_file" ]]; then
        log_error "Backup file not found: $BACKUP_DIR/$backup_file"
        exit 1
    fi
    
    log_warn "This will REPLACE all Superset metadata (dashboards, charts, users)!"
    read -p "Are you sure? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log_info "Restore cancelled."
        exit 0
    fi
    
    log_info "Restoring Superset metadata from $backup_file..."
    
    # Drop and recreate database
    docker exec "$METADATA_CONTAINER" psql -U superset -d postgres -c "DROP DATABASE IF EXISTS superset;"
    docker exec "$METADATA_CONTAINER" psql -U superset -d postgres -c "CREATE DATABASE superset;"
    
    # Restore
    gunzip -c "$BACKUP_DIR/$backup_file" | docker exec -i "$METADATA_CONTAINER" psql -U superset -d superset
    
    log_info "Metadata restore complete!"
    log_warn "You may need to restart Superset: docker compose restart superset"
}

list_backups() {
    log_info "Available backups in $BACKUP_DIR:"
    echo ""
    
    if [[ -d "$BACKUP_DIR" ]] && [[ -n "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        ls -lh "$BACKUP_DIR"/*.sql.gz 2>/dev/null || log_warn "No .sql.gz files found"
        echo ""
        ls -lh "$BACKUP_DIR"/*_manifest.txt 2>/dev/null || true
    else
        log_warn "No backups found."
    fi
}

cleanup_old_backups() {
    local days="${1:-30}"
    log_info "Removing backups older than $days days..."
    
    find "$BACKUP_DIR" -name "*.sql.gz" -mtime +$days -delete
    find "$BACKUP_DIR" -name "*_manifest.txt" -mtime +$days -delete
    
    log_info "Cleanup complete."
}

usage() {
    cat << EOF
Database Backup & Restore Script for Giga MST

Usage: $0 <command> [options]

Commands:
  backup [all|data|metadata]    Create backup (default: all)
  restore <data|metadata> FILE  Restore from backup file
  list                          List available backups
  cleanup [days]                Remove backups older than N days (default: 30)

Examples:
  $0 backup                     # Backup both databases
  $0 backup data                # Backup only MST data
  $0 restore data mst_data_20260130_120000.sql.gz
  $0 list
  $0 cleanup 7                  # Remove backups older than 7 days

Environment variables:
  BACKUP_DIR    Backup directory (default: ./backups)
EOF
}

# Main
case "${1:-help}" in
    backup)
        case "${2:-all}" in
            all) backup_all ;;
            data) backup_data_db ;;
            metadata) backup_metadata_db ;;
            *) usage; exit 1 ;;
        esac
        ;;
    restore)
        if [[ -z "${2:-}" ]] || [[ -z "${3:-}" ]]; then
            log_error "Usage: $0 restore <data|metadata> <backup_file>"
            exit 1
        fi
        case "$2" in
            data) restore_data_db "$3" ;;
            metadata) restore_metadata_db "$3" ;;
            *) usage; exit 1 ;;
        esac
        ;;
    list)
        list_backups
        ;;
    cleanup)
        cleanup_old_backups "${2:-30}"
        ;;
    help|*)
        usage
        ;;
esac
