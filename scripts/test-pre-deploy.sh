#!/bin/bash
# Pre-deployment validation. Verifies prerequisites before running the stack.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
cd "$PROJECT_DIR"

echo "======================================"
echo "Pre-Deployment Tests"
echo "======================================"
echo ""

# Docker daemon
echo -n "Docker daemon... "
if docker info &>/dev/null; then
    test_pass "Docker is running"
else
    test_fail "Docker is not running"
fi

# Docker Compose
echo -n "Docker Compose v2... "
if docker compose version &>/dev/null; then
    test_pass "available"
else
    test_fail "not available"
fi

# GPU access
echo -n "GPU access... "
if docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi &>/dev/null; then
    test_pass "NVIDIA GPU accessible"
else
    test_fail "NVIDIA GPU not accessible"
fi

# Environment
echo -n "Environment... "
if [[ -f .env ]]; then
    load_env
    missing=""
    for var in FRIGATE_RTSP_PASSWORD DOORBELL_IP HOST_IP SYNOLOGY_IP SYNOLOGY_NFS_EXPORT; do
        val="${!var:-}"
        if [[ -z "$val" || "$val" == *"x.x"* || "$val" == *"password_here"* || "$val" == *"changeme"* ]]; then
            missing="$missing $var"
        fi
    done
    if [[ -z "$missing" ]]; then
        test_pass "All required variables set"
    else
        test_fail "Missing or invalid:$missing"
    fi
else
    test_fail ".env file not found"
fi

# NFS mount
echo -n "NFS mount... "
load_env 2>/dev/null || true
mount_path="${NFS_FRIGATE_PATH:-/mnt/synology/frigate}"
if mountpoint -q "$mount_path" 2>/dev/null; then
    test_pass "NFS mounted at $mount_path"
else
    test_fail "NFS not mounted at $mount_path"
fi

# NFS writable
echo -n "NFS writable... "
if touch "$mount_path/.test" 2>/dev/null && rm "$mount_path/.test" 2>/dev/null; then
    test_pass "writable (user)"
elif sudo touch "$mount_path/.test" 2>/dev/null && sudo rm "$mount_path/.test" 2>/dev/null; then
    test_warn "writable as root only (OK for Docker)"
else
    test_fail "NFS is not writable"
fi

# Frigate config syntax
echo -n "Frigate config... "
if python3 -c "import yaml; yaml.safe_load(open('frigate/config/config.yml'))" 2>/dev/null; then
    test_pass "valid YAML"
else
    test_fail "invalid YAML"
fi

# Docker Compose syntax
echo -n "Docker Compose config... "
if docker compose config &>/dev/null; then
    test_pass "valid"
else
    test_fail "has errors"
fi

# Required tools
echo -n "Required tools... "
if require_commands curl jq nc 2>/dev/null; then
    test_pass "all installed"
else
    test_fail "missing tools (see above)"
fi

test_summary "Results"
