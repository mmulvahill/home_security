#!/bin/bash
# Post-deployment validation. Verifies all services are running correctly.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
cd "$PROJECT_DIR"

echo "======================================"
echo "Post-Deployment Tests"
echo "======================================"
echo ""

# MQTT broker
echo -n "MQTT broker... "
if timeout 5 mosquitto_sub -h localhost -t '$SYS/broker/uptime' -C 1 &>/dev/null; then
    test_pass "responding"
else
    test_fail "not responding"
fi

# Frigate API
echo -n "Frigate API... "
if curl -sf http://localhost:5000/api/version &>/dev/null; then
    version=$(curl -sf http://localhost:5000/api/version)
    test_pass "responding (version: $version)"
else
    test_fail "not responding"
fi

# Frigate cameras
echo -n "Frigate cameras... "
if curl -sf http://localhost:5000/api/stats &>/dev/null; then
    camera_count=$(curl -sf http://localhost:5000/api/stats | jq -r '.cameras | length' 2>/dev/null || echo "0")
    if [[ "$camera_count" == "0" ]]; then
        test_warn "no cameras configured"
    else
        test_pass "$camera_count camera(s) configured"
    fi
else
    test_fail "cannot query Frigate stats"
fi

# MQTT message flow
echo -n "MQTT from Frigate... "
if timeout 30 mosquitto_sub -h localhost -t 'frigate/available' -C 1 &>/dev/null; then
    test_pass "publishing"
else
    test_warn "no messages in 30s"
fi

# GPU
echo -n "GPU... "
if nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits -i 0 &>/dev/null; then
    gpu_util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits -i 0)
    test_pass "GPU 0 accessible (${gpu_util}% util)"
else
    test_fail "cannot query GPU"
fi

# Recording storage
echo -n "Recording storage... "
load_env 2>/dev/null || true
mount_path="${NFS_FRIGATE_PATH:-/mnt/synology/frigate}"
if mountpoint -q "$mount_path" 2>/dev/null; then
    avail=$(df -h "$mount_path" | awk 'NR==2 {print $4}')
    test_pass "$avail available"
else
    test_fail "NFS not mounted"
fi

# Container health
echo -n "Container health... "
unhealthy=$(docker ps --filter "health=unhealthy" --format '{{.Names}}' | tr '\n' ' ')
if [[ -z "$unhealthy" ]]; then
    test_pass "all healthy"
else
    test_fail "unhealthy: $unhealthy"
fi

# Restart counts
echo -n "Container restarts... "
high_restarts=$(docker ps --format '{{.Names}}' | while read -r name; do
    count=$(docker inspect "$name" --format '{{.RestartCount}}' 2>/dev/null || echo "0")
    [[ "$count" -gt 5 ]] && echo "$name($count)"
done)
if [[ -z "$high_restarts" ]]; then
    test_pass "no excessive restarts"
else
    test_warn "high restarts: $high_restarts"
fi

test_summary "Results"
