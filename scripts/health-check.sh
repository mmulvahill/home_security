#!/bin/bash
# Health check - runs via cron every 5 minutes.
# Checks services, disk, GPU, and auto-restarts failed containers.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
cd "$PROJECT_DIR"

load_env 2>/dev/null || true

ALERT_FILE="/tmp/security-stack-alerts"
MQTT_TOPIC="security-stack/health"

> "$ALERT_FILE"

alert() {
    echo "$(date -Iseconds) $1" >> "$ALERT_FILE"
    mosquitto_pub -h localhost -t "$MQTT_TOPIC" \
        -m "{\"status\":\"alert\",\"message\":\"$1\",\"timestamp\":\"$(date -Iseconds)\"}" \
        2>/dev/null || true
}

check_service() {
    local name="$1"
    if ! docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
        alert "Service $name is not running"
        return 1
    fi
    local restarts
    restarts=$(docker inspect "$name" --format '{{.RestartCount}}' 2>/dev/null || echo "0")
    [[ "$restarts" -gt 5 ]] && alert "Service $name has restarted $restarts times"
    return 0
}

auto_restart() {
    for svc in mqtt frigate compreface double-take; do
        if ! docker ps --format '{{.Names}}' | grep -q "^${svc}$"; then
            echo "Auto-restarting $svc..."
            docker compose -f "${PROJECT_DIR}/docker-compose.yml" up -d "$svc"
        fi
    done
}

check_disk() {
    local mount_point="${NFS_FRIGATE_PATH:-/mnt/synology/frigate}"
    if ! mountpoint -q "$mount_point" 2>/dev/null; then
        alert "NFS mount $mount_point is not mounted"
        return 1
    fi
    local usage
    usage=$(df "$mount_point" | awk 'NR==2 {print int($5)}')
    [[ "$usage" -gt 90 ]] && alert "Disk usage on $mount_point is ${usage}%"
}

check_cameras() {
    if ! curl -sf http://localhost:5000/api/stats &>/dev/null; then
        alert "Cannot connect to Frigate API"
        return 1
    fi
    local dead_cams
    dead_cams=$(curl -sf http://localhost:5000/api/stats | jq -r '.cameras // {} | to_entries[] | select(.value.camera_fps == 0) | .key' 2>/dev/null || echo "")
    [[ -n "$dead_cams" ]] && alert "Camera(s) disconnected: $dead_cams"
}

check_gpu() {
    if ! nvidia-smi &>/dev/null; then
        alert "GPU not responding"
        return 1
    fi
    local gpu_count
    gpu_count=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -1)
    for i in $(seq 0 $((gpu_count - 1))); do
        local mem
        mem=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits -i "$i" | awk '{print int($1)}')
        [[ "$mem" -gt 20000 ]] && alert "GPU $i memory high: ${mem}MB"
    done
}

# Run checks
for svc in mqtt frigate compreface double-take; do
    check_service "$svc" || auto_restart
done

check_disk
check_cameras || true
check_gpu

# Report
if [[ ! -s "$ALERT_FILE" ]]; then
    mosquitto_pub -h localhost -t "$MQTT_TOPIC" \
        -m "{\"status\":\"healthy\",\"timestamp\":\"$(date -Iseconds)\"}" \
        2>/dev/null || true
else
    cat "$ALERT_FILE"
fi
