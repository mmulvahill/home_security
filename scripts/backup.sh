#!/bin/bash
# Backup script for home security stack
# Run daily via cron at 3 AM

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

BACKUP_DIR="${BACKUP_DIR:-/mnt/synology/frigate/backups}"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="security-stack-backup-${DATE}.tar.gz"

echo "Starting backup at $(date)"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Create temporary backup directory
TMP_BACKUP="/tmp/security-backup-$$"
mkdir -p "$TMP_BACKUP"

# Copy configuration files
echo "Backing up configuration files..."
cp .env.example "$TMP_BACKUP/"
cp docker-compose.yml "$TMP_BACKUP/"
cp -r frigate/config "$TMP_BACKUP/frigate-config"
cp -r mosquitto/config "$TMP_BACKUP/mosquitto-config"
cp double-take/config.yml "$TMP_BACKUP/double-take-config.yml" 2>/dev/null || true
cp -r scripts "$TMP_BACKUP/" 2>/dev/null || true
cp Makefile "$TMP_BACKUP/" 2>/dev/null || true
cp README.md "$TMP_BACKUP/" 2>/dev/null || true

# Backup Frigate database
echo "Backing up Frigate database..."
if [[ -f frigate/config/frigate.db ]]; then
    cp frigate/config/frigate.db "$TMP_BACKUP/"
fi

# Create tarball
echo "Creating backup archive..."
tar -czf "${BACKUP_DIR}/${BACKUP_FILE}" -C "$TMP_BACKUP" .

# Cleanup temp directory
rm -rf "$TMP_BACKUP"

# Keep only last 30 backups
echo "Cleaning old backups..."
cd "$BACKUP_DIR"
ls -t security-stack-backup-*.tar.gz | tail -n +31 | xargs -r rm

echo "Backup complete: ${BACKUP_DIR}/${BACKUP_FILE}"
echo "Backup size: $(du -h ${BACKUP_DIR}/${BACKUP_FILE} | cut -f1)"

# Send success notification to MQTT
mosquitto_pub -h localhost -t "security-stack/backup" \
  -m "{\"status\":\"success\",\"file\":\"${BACKUP_FILE}\",\"timestamp\":\"$(date -Iseconds)\"}" \
  2>/dev/null || true
