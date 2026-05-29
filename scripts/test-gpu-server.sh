#!/bin/bash
# GPU server capability test. Run before first deployment.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
cd "$PROJECT_DIR"

echo "=========================================="
echo "GPU Server Testing"
echo "=========================================="
echo ""

# Docker daemon
echo -n "Docker daemon... "
if docker info &>/dev/null; then
    test_pass "running"
else
    test_fail "not running (run: sudo usermod -aG docker \$USER, then re-login)"
    exit 1
fi

# Docker Compose
echo -n "Docker Compose... "
if docker compose version &>/dev/null; then
    test_pass "v$(docker compose version --short)"
else
    test_fail "not available"
fi

# GPU detection
echo -n "NVIDIA GPUs... "
if nvidia-smi &>/dev/null; then
    gpu_count=$(nvidia-smi -L | wc -l)
    test_pass "$gpu_count GPU(s) detected"
    nvidia-smi -L | sed 's/^/       /'
else
    test_fail "nvidia-smi not working"
fi

# GPU in Docker
echo -n "GPU access in Docker... "
if docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi -L &>/dev/null; then
    test_pass "Docker can access GPUs"
else
    test_fail "Docker cannot access GPUs (install: sudo apt install nvidia-container-toolkit)"
fi

# Compose config
echo -n "docker-compose.yml... "
if docker compose config &>/dev/null; then
    test_pass "valid"
else
    test_fail "has errors"
fi

# .env file
echo -n ".env file... "
if [[ -f .env ]]; then
    test_pass "found"
    load_env
    echo "       HOST_IP: $HOST_IP"
    echo "       SYNOLOGY_IP: $SYNOLOGY_IP"
else
    test_fail "not found (run: cp .env.example .env)"
fi

# Required tools
echo -n "Required tools... "
if require_commands jq nc curl 2>/dev/null; then
    test_pass "all installed"
else
    test_fail "missing tools"
fi

# Pull images
echo ""
echo "Pulling Docker images (may take 10-15 minutes on first run)..."
echo ""

images=(
    "eclipse-mosquitto:2"
    "ghcr.io/blakeblackshear/frigate:stable-tensorrt"
)
for image in "${images[@]}"; do
    echo -n "Pulling $image... "
    if docker pull "$image" &>/dev/null; then
        test_pass "done"
    else
        test_fail "failed"
    fi
done

test_summary "Results"
