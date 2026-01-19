#!/bin/bash
# Pre-deployment tests
# Verifies prerequisites before running the stack

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

PASSED=0
FAILED=0

test_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    PASSED=$((PASSED + 1))
}

test_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    FAILED=$((FAILED + 1))
}

echo "======================================"
echo "Pre-Deployment Tests"
echo "======================================"
echo ""

# Test 1: Docker daemon
echo -n "Docker daemon... "
if docker info &>/dev/null; then
    test_pass "Docker is running"
else
    test_fail "Docker is not running"
fi

# Test 2: Docker Compose
echo -n "Docker Compose v2... "
if docker compose version &>/dev/null; then
    test_pass "Docker Compose v2 available"
else
    test_fail "Docker Compose v2 not available"
fi

# Test 3: GPU access
echo -n "GPU access... "
if docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi &>/dev/null; then
    test_pass "NVIDIA GPU accessible"
else
    test_fail "NVIDIA GPU not accessible"
fi

# Test 4: NFS mount
echo -n "NFS mount... "
if [[ -f .env ]]; then
    source .env
    MOUNT_PATH="${NFS_FRIGATE_PATH:-/mnt/synology/frigate}"
    if mountpoint -q "$MOUNT_PATH" 2>/dev/null; then
        test_pass "NFS mounted at $MOUNT_PATH"
    else
        test_fail "NFS not mounted at $MOUNT_PATH"
    fi
else
    test_fail ".env file not found"
fi

# Test 5: NFS writable
if [[ -f .env ]]; then
    source .env
    MOUNT_PATH="${NFS_FRIGATE_PATH:-/mnt/synology/frigate}"
    echo -n "NFS writable... "
    if touch "$MOUNT_PATH/.test" 2>/dev/null && rm "$MOUNT_PATH/.test" 2>/dev/null; then
        test_pass "NFS is writable"
    else
        test_fail "NFS is not writable"
    fi
fi

# Test 6: Environment variables
echo -n "Environment... "
if [[ -f .env ]]; then
    source .env
    REQUIRED_VARS=(FRIGATE_RTSP_PASSWORD DOORBELL_IP HOST_IP SYNOLOGY_IP)
    MISSING=""
    for var in "${REQUIRED_VARS[@]}"; do
        if [[ -z "${!var:-}" ]] || [[ "${!var}" == *"x.x"* ]] || [[ "${!var}" == *"password_here"* ]]; then
            MISSING="$MISSING $var"
        fi
    done
    if [[ -z "$MISSING" ]]; then
        test_pass "All required variables set"
    else
        test_fail "Missing or invalid variables:$MISSING"
    fi
else
    test_fail ".env file not found"
fi

# Test 7: Frigate config syntax
echo -n "Frigate config syntax... "
if command -v python3 &>/dev/null; then
    if python3 -c "import yaml; yaml.safe_load(open('frigate/config/config.yml'))" 2>/dev/null; then
        test_pass "Frigate config valid YAML"
    else
        test_fail "Frigate config has syntax errors"
    fi
else
    test_fail "Python3 not available to validate YAML"
fi

# Test 8: Docker Compose syntax
echo -n "Docker Compose syntax... "
if docker compose config &>/dev/null; then
    test_pass "docker-compose.yml is valid"
else
    test_fail "docker-compose.yml has syntax errors"
fi

# Test 9: Required tools
echo -n "Required tools... "
MISSING_TOOLS=""
for tool in curl jq nc; do
    if ! command -v $tool &>/dev/null; then
        MISSING_TOOLS="$MISSING_TOOLS $tool"
    fi
done
if [[ -z "$MISSING_TOOLS" ]]; then
    test_pass "All required tools installed"
else
    test_fail "Missing tools:$MISSING_TOOLS"
fi

echo ""
echo "======================================"
echo "Results"
echo "======================================"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}All pre-deployment tests passed!${NC}"
    echo "Ready to run: make setup"
    exit 0
else
    echo -e "${RED}Some tests failed. Fix issues before deploying.${NC}"
    exit 1
fi
