#!/bin/bash
# GPU Server Testing Script
# Run this in a terminal where docker group is active

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

test_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

echo "=========================================="
echo "GPU Server Testing"
echo "=========================================="
echo ""

# Test 1: Docker daemon
echo -n "Docker daemon... "
if docker info &>/dev/null; then
    test_pass "Docker running"
else
    test_fail "Cannot connect to Docker daemon"
    echo "       Run: sudo usermod -aG docker \$USER"
    echo "       Then log out and log back in"
    exit 1
fi

# Test 2: Docker Compose
echo -n "Docker Compose... "
if docker compose version &>/dev/null; then
    VERSION=$(docker compose version --short)
    test_pass "v$VERSION available"
else
    test_fail "Docker Compose not available"
fi

# Test 3: GPU detection
echo -n "NVIDIA GPUs... "
if nvidia-smi &>/dev/null; then
    GPU_COUNT=$(nvidia-smi -L | wc -l)
    test_pass "$GPU_COUNT GPU(s) detected"
    nvidia-smi -L | sed 's/^/       /'
else
    test_fail "nvidia-smi not working"
fi

# Test 4: GPU access through Docker
echo -n "GPU access in Docker... "
if docker run --rm --gpus all nvidia/cuda:12.0-base-ubuntu22.04 nvidia-smi -L &>/dev/null; then
    test_pass "Docker can access GPUs"
else
    test_fail "Docker cannot access GPUs"
    echo "       Install: sudo apt install nvidia-container-toolkit"
fi

# Test 5: Docker Compose config
echo -n "docker-compose.yml... "
if docker compose config &>/dev/null; then
    test_pass "Valid configuration"
else
    test_fail "Configuration has errors"
fi

# Test 6: Check .env file
echo -n ".env file... "
if [[ -f .env ]]; then
    test_pass "Found"

    # Check critical values
    source .env
    echo "       HOST_IP: $HOST_IP"
    echo "       SYNOLOGY_IP: $SYNOLOGY_IP"

    if [[ "$FRIGATE_RTSP_PASSWORD" == "changeme_camera_password" ]]; then
        echo -e "       ${YELLOW}WARNING: Update FRIGATE_RTSP_PASSWORD${NC}"
    fi
else
    test_fail "Not found"
    echo "       Run: cp .env.example .env"
fi

# Test 7: Required tools
echo -n "Required tools... "
MISSING=""
for tool in jq nc curl; do
    if ! command -v $tool &>/dev/null; then
        MISSING="$MISSING $tool"
    fi
done
if [[ -z "$MISSING" ]]; then
    test_pass "All tools installed"
else
    test_fail "Missing:$MISSING"
    echo "       Run: sudo apt install${MISSING}"
fi

# Test 8: Pull core images
echo ""
echo "Pulling Docker images (this may take 10-15 minutes)..."
echo ""

IMAGES=(
    "eclipse-mosquitto:2"
    "ghcr.io/blakeblackshear/frigate:stable-tensorrt"
    "postgres:11.5"
    "exadel/compreface-admin:latest"
    "exadel/compreface-api:latest"
    "exadel/compreface-fe:latest"
    "jakowenko/double-take:latest"
)

for image in "${IMAGES[@]}"; do
    echo -n "Pulling $image... "
    if docker pull $image &>/dev/null; then
        test_pass "Done"
    else
        test_fail "Failed"
    fi
done

echo ""
echo "=========================================="
echo "Results"
echo "=========================================="
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ GPU server ready for deployment!${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Update .env with your Synology IP"
    echo "2. Update FRIGATE_RTSP_PASSWORD in .env"
    echo "3. Check NFS: cat scripts/test-nfs.sh"
    echo "4. When ready: make setup"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
