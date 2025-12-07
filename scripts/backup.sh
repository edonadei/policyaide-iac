#!/bin/bash
set -euo pipefail

#######################################
# Firecrawl Production Backup Script
# Creates backups of data and configuration
#######################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${PROJECT_ROOT}/backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="firecrawl-backup-${TIMESTAMP}"

echo "=========================================="
echo "Firecrawl Production Backup"
echo "=========================================="
echo "Backup name: $BACKUP_NAME"
echo ""

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Export Docker volumes
echo "Backing up PostgreSQL data..."
docker run --rm \
    -v firecrawl-plus-rotating-vpn_postgres_data:/data \
    -v "$BACKUP_DIR":/backup \
    alpine tar czf "/backup/${BACKUP_NAME}-postgres.tar.gz" -C /data .

echo "Backing up Redis data..."
docker run --rm \
    -v firecrawl-plus-rotating-vpn_redis_data:/data \
    -v "$BACKUP_DIR":/backup \
    alpine tar czf "/backup/${BACKUP_NAME}-redis.tar.gz" -C /data .

echo "Backing up Grafana data..."
docker run --rm \
    -v firecrawl-plus-rotating-vpn_grafana_data:/data \
    -v "$BACKUP_DIR":/backup \
    alpine tar czf "/backup/${BACKUP_NAME}-grafana.tar.gz" -C /data .

echo "Backing up Prometheus data..."
docker run --rm \
    -v firecrawl-plus-rotating-vpn_prometheus_data:/data \
    -v "$BACKUP_DIR":/backup \
    alpine tar czf "/backup/${BACKUP_NAME}-prometheus.tar.gz" -C /data .

# Backup configuration files
echo "Backing up configuration..."
tar czf "$BACKUP_DIR/${BACKUP_NAME}-config.tar.gz" \
    -C "$PROJECT_ROOT" \
    docker-compose.yml \
    nginx/nginx.conf \
    monitoring/ \
    grafana/ \
    scripts/ \
    .env 2>/dev/null || true  # Ignore if .env doesn't exist

# Create backup manifest
cat > "$BACKUP_DIR/${BACKUP_NAME}-manifest.txt" <<EOF
Firecrawl Production Backup
Created: $(date)
Hostname: $(hostname)
Docker Version: $(docker --version)

Backup Contents:
- PostgreSQL data: ${BACKUP_NAME}-postgres.tar.gz
- Redis data: ${BACKUP_NAME}-redis.tar.gz
- Grafana data: ${BACKUP_NAME}-grafana.tar.gz
- Prometheus data: ${BACKUP_NAME}-prometheus.tar.gz
- Configuration: ${BACKUP_NAME}-config.tar.gz

To restore:
1. Extract config: tar xzf ${BACKUP_NAME}-config.tar.gz
2. Import volumes using docker run commands (see backup.sh)
3. Run deployment: ./scripts/deploy.sh
EOF

# Calculate sizes
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)

echo ""
echo "=========================================="
echo "Backup Complete!"
echo "=========================================="
echo "Location: $BACKUP_DIR"
echo "Total size: $TOTAL_SIZE"
echo ""
ls -lh "$BACKUP_DIR/${BACKUP_NAME}"*
echo ""

# Cleanup old backups (keep last 7)
echo "Cleaning up old backups (keeping last 7)..."
cd "$BACKUP_DIR"
ls -t firecrawl-backup-* 2>/dev/null | tail -n +8 | xargs rm -f 2>/dev/null || true
echo "Done!"
