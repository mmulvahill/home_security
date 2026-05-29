#!/bin/bash
# Backup configurations. Run daily via cron at 3 AM.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
cd "$PROJECT_DIR"

load_env 2>/dev/null || true

BACKUP_DIR="${BACKUP_DIR:-${NFS_FRIGATE_PATH:-/mnt/synology/frigate}/backups}"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="security-stack-backup-${DATE}.tar.gz"
TMP_BACKUP="/tmp/security-backup-$$"

mkdir -p "$BACKUP_DIR" "$TMP_BACKUP"

echo "Starting backup at $(date)"

# Config files
cp .env.example "$TMP_BACKUP/"
cp docker-compose.yml "$TMP_BACKUP/"
cp -r frigate/config "$TMP_BACKUP/frigate-config"
cp -r mosquitto/config "$TMP_BACKUP/mosquitto-config"
cp -r scripts "$TMP_BACKUP/"
cp Makefile "$TMP_BACKUP/"

# Frigate database
[[ -f frigate/config/frigate.db ]] && cp frigate/config/frigate.db "$TMP_BACKUP/"

# Archive
tar -czf "${BACKUP_DIR}/${BACKUP_FILE}" -C "$TMP_BACKUP" .
rm -rf "$TMP_BACKUP"

# Retain last 30
cd "$BACKUP_DIR"
ls -t security-stack-backup-*.tar.gz 2>/dev/null | tail -n +31 | xargs -r rm

echo "Backup complete: ${BACKUP_DIR}/${BACKUP_FILE}"
echo "Size: $(du -h "${BACKUP_DIR}/${BACKUP_FILE}" | cut -f1)"

mosquitto_pub -h localhost -t "security-stack/backup" \
    -m "{\"status\":\"success\",\"file\":\"${BACKUP_FILE}\",\"timestamp\":\"$(date -Iseconds)\"}" \
    2>/dev/null || true
