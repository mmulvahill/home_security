#!/bin/bash
# Home Security Stack - Health Check Script
# Run via cron every 5 minutes to monitor system health

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# Load environment
if [[ -f .env ]]; then
    source .env
fi

ALERT_FILE="/tmp/security-stack-alerts"
MQTT_TOPIC="security-stack/health"

log_alert() {
    local message="$1"
    echo "$(date -Iseconds) $message" >> "$ALERT_FILE"
    # Publish to MQTT for Home Assistant
    mosquitto_pub -h localhost -t "$MQTT_TOPIC" -m "{\"status\":\"alert\",\"message\":\"$message\",\"timestamp\":\"$(date -Iseconds)\"}" 2>/dev/null || true
}

check_service() {
    local name="$1"
    if ! docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
        log_alert "Service $name is not running"
        return 1
    fi

    # Check if restarting frequently
    local restart_count=$(docker inspect "$name" --format '{{.RestartCount}}' 2>/dev/null || echo "0")
    if [[ "$restart_count" -gt 5 ]]; then
        log_alert "Service $name has restarted $restart_count times"
    fi

    return 0
}

check_disk_space() {
    local mount_point="${NFS_FRIGATE_PATH:-/mnt/synology/frigate}"
    local threshold=90

    if ! mountpoint -q "$mount_point" 2>/dev/null; then
        log_alert "NFS mount $mount_point is not mounted"
        return 1
    fi

    local usage=$(df "$mount_point" | awk 'NR==2 {print int($5)}')
    if [[ "$usage" -gt "$threshold" ]]; then
        log_alert "Disk usage on $mount_point is ${usage}%"
    fi
}

check_camera_connection() {
    # Check if Frigate can see the cameras
    if ! curl -sf http://localhost:5000/api/stats &>/dev/null; then
        log_alert "Cannot connect to Frigate API"
        return 1
    fi

    # Get camera stats
    local camera_fps=$(curl -sf http://localhost:5000/api/stats | jq -r '.cameras // {} | to_entries[] | select(.value.camera_fps == 0) | .key' 2>/dev/null || echo "")

    if [[ -n "$camera_fps" ]]; then
        log_alert "Camera(s) appear disconnected: $camera_fps"
    fi
}

check_gpu() {
    if ! nvidia-smi &>/dev/null; then
        log_alert "GPU not responding to nvidia-smi"
        return 1
    fi

    # Check GPU memory usage (warn if > 20GB on any GPU)
    local gpu_count=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -1)
    for i in $(seq 0 $((gpu_count - 1))); do
        local gpu_mem=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits -i "$i" | awk '{print int($1)}')
        if [[ "$gpu_mem" -gt 20000 ]]; then
            log_alert "GPU $i memory usage high: ${gpu_mem}MB"
        fi
    done
}

check_mqtt() {
    if ! timeout 5 mosquitto_sub -h localhost -t '$SYS/broker/uptime' -C 1 &>/dev/null; then
        log_alert "MQTT broker not responding"
        return 1
    fi
}

auto_restart_services() {
    # Auto-restart failed core services
    local services=(mqtt frigate compreface double-take)
    for service in "${services[@]}"; do
        if ! docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
            echo "Auto-restarting $service..."
            docker compose up -d "$service"
        fi
    done
}

main() {
    # Clear previous alerts
    > "$ALERT_FILE"

    # Check all services
    check_service "mqtt" || auto_restart_services
    check_service "frigate" || auto_restart_services
    check_service "compreface" || auto_restart_services
    check_service "double-take" || auto_restart_services

    check_mqtt
    check_disk_space
    check_camera_connection || true  # Don't fail if no cameras yet
    check_gpu

    # If no alerts, publish healthy status
    if [[ ! -s "$ALERT_FILE" ]]; then
        mosquitto_pub -h localhost -t "$MQTT_TOPIC" -m "{\"status\":\"healthy\",\"timestamp\":\"$(date -Iseconds)\"}" 2>/dev/null || true
    else
        # Display alerts
        cat "$ALERT_FILE"
    fi
}

main "$@"
