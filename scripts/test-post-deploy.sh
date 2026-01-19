#!/bin/bash
# Post-deployment tests
# Verifies that all services are running correctly

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0
WARNED=0

test_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    PASSED=$((PASSED + 1))
}

test_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    FAILED=$((FAILED + 1))
}

test_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    WARNED=$((WARNED + 1))
}

echo "======================================"
echo "Post-Deployment Tests"
echo "======================================"
echo ""

# Test 1: MQTT broker
echo -n "MQTT broker... "
if timeout 5 mosquitto_sub -h localhost -t '$SYS/broker/uptime' -C 1 &>/dev/null; then
    test_pass "MQTT broker responding"
else
    test_fail "MQTT broker not responding"
fi

# Test 2: Frigate API
echo -n "Frigate API... "
if curl -sf http://localhost:5000/api/version &>/dev/null; then
    VERSION=$(curl -sf http://localhost:5000/api/version)
    test_pass "Frigate API responding (version: $VERSION)"
else
    test_fail "Frigate API not responding"
fi

# Test 3: Frigate camera status
echo -n "Frigate cameras... "
if curl -sf http://localhost:5000/api/stats &>/dev/null; then
    CAMERA_COUNT=$(curl -sf http://localhost:5000/api/stats | jq -r '.cameras | length' 2>/dev/null || echo "0")
    if [[ "$CAMERA_COUNT" == "0" ]]; then
        test_warn "No cameras configured yet (expected until hardware arrives)"
    else
        test_pass "$CAMERA_COUNT camera(s) configured"
    fi
else
    test_fail "Cannot query Frigate stats"
fi

# Test 4: CompreFace API
echo -n "CompreFace UI... "
if curl -sf http://localhost:8000 &>/dev/null; then
    test_pass "CompreFace UI accessible"
else
    test_fail "CompreFace UI not accessible"
fi

# Test 5: Double-Take API
echo -n "Double-Take... "
if curl -sf http://localhost:3000 &>/dev/null; then
    test_pass "Double-Take UI accessible"
else
    test_fail "Double-Take UI not accessible"
fi

# Test 6: MQTT message flow
echo -n "MQTT message flow... "
if timeout 30 mosquitto_sub -h localhost -t 'frigate/available' -C 1 &>/dev/null; then
    test_pass "Frigate publishing to MQTT"
else
    test_warn "No MQTT messages from Frigate in 30s"
fi

# Test 7: GPU utilization
echo -n "GPU utilization... "
if nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits -i 0 &>/dev/null; then
    GPU_UTIL=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits -i 0)
    test_pass "GPU 0 accessible (${GPU_UTIL}% utilization)"
else
    test_fail "Cannot query GPU status"
fi

# Test 8: Recording storage
echo -n "Recording storage... "
if [[ -f .env ]]; then
    source .env
    MOUNT_PATH="${NFS_FRIGATE_PATH:-/mnt/synology/frigate}"
    if mountpoint -q "$MOUNT_PATH" 2>/dev/null; then
        STORAGE=$(df -h "$MOUNT_PATH" | awk 'NR==2 {print $4}')
        test_pass "Storage available: $STORAGE"
    else
        test_fail "NFS not mounted"
    fi
else
    test_fail ".env not found"
fi

# Test 9: Container health
echo -n "Container health... "
UNHEALTHY=$(docker ps --filter "health=unhealthy" --format '{{.Names}}' | wc -l)
if [[ "$UNHEALTHY" -eq 0 ]]; then
    test_pass "All containers healthy"
else
    UNHEALTHY_LIST=$(docker ps --filter "health=unhealthy" --format '{{.Names}}' | tr '\n' ' ')
    test_fail "Unhealthy containers: $UNHEALTHY_LIST"
fi

# Test 10: Container restart count
echo -n "Container restarts... "
HIGH_RESTARTS=$(docker ps --format '{{.Names}}' | while read name; do
    COUNT=$(docker inspect "$name" --format '{{.RestartCount}}' 2>/dev/null || echo "0")
    if [[ "$COUNT" -gt 5 ]]; then
        echo "$name($COUNT)"
    fi
done)
if [[ -z "$HIGH_RESTARTS" ]]; then
    test_pass "No excessive restarts"
else
    test_warn "High restart counts: $HIGH_RESTARTS"
fi

echo ""
echo "======================================"
echo "Results"
echo "======================================"
echo "Passed: $PASSED"
echo "Warned: $WARNED"
echo "Failed: $FAILED"
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}Post-deployment tests passed!${NC}"
    if [[ $WARNED -gt 0 ]]; then
        echo -e "${YELLOW}Some warnings noted above.${NC}"
    fi
    exit 0
else
    echo -e "${RED}Some tests failed. Check logs for details.${NC}"
    exit 1
fi
