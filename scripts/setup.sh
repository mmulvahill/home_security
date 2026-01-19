#!/bin/bash
# Home Security Stack - Initial Setup Script
# Sets up the complete security stack on the GPU server

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."

    # Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker not installed"
        exit 1
    fi
    log_info "Docker: $(docker --version)"

    # Docker Compose v2
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose v2 not available"
        exit 1
    fi
    log_info "Docker Compose: $(docker compose version)"

    # NVIDIA Container Toolkit
    log_info "Testing NVIDIA GPU access..."
    if ! docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi &> /dev/null; then
        log_error "NVIDIA Container Toolkit not working"
        log_error "Install with: sudo apt install nvidia-container-toolkit"
        exit 1
    fi
    log_info "GPU access working"

    # NFS client
    if ! command -v mount.nfs &> /dev/null; then
        log_warn "NFS client not installed - installing..."
        sudo apt-get update && sudo apt-get install -y nfs-common
    fi
    log_info "NFS client available"

    # Check for jq (used in health checks)
    if ! command -v jq &> /dev/null; then
        log_warn "jq not installed - installing..."
        sudo apt-get update && sudo apt-get install -y jq
    fi

    log_info "✓ Prerequisites OK"
}

# Setup environment file
setup_env() {
    log_step "Setting up environment..."

    if [[ ! -f .env ]]; then
        if [[ -f .env.example ]]; then
            cp .env.example .env
            log_warn "Created .env from template"
            log_error "EDIT .env FILE with your values before continuing"
            log_error "Required: FRIGATE_RTSP_PASSWORD, DOORBELL_IP, HOST_IP, SYNOLOGY_IP"
            echo ""
            echo "Edit the file and then run this script again."
            exit 1
        else
            log_error ".env.example not found"
            exit 1
        fi
    fi

    # Validate required variables
    source .env
    local required_vars=(FRIGATE_RTSP_PASSWORD DOORBELL_IP HOST_IP SYNOLOGY_IP)
    local missing=0
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]] || [[ "${!var}" == *"x.x"* ]] || [[ "${!var}" == *"password_here"* ]]; then
            log_error "Missing or invalid value for: $var"
            missing=1
        fi
    done

    if [[ $missing -eq 1 ]]; then
        log_error "Please configure all required variables in .env"
        exit 1
    fi

    log_info "✓ Environment OK"
}

# Setup NFS mount
setup_nfs() {
    log_step "Setting up NFS mount..."

    source .env
    local mount_point="${NFS_FRIGATE_PATH:-/mnt/synology/frigate}"
    local nfs_export="${SYNOLOGY_IP}:/volume1/frigate"

    # Create mount point
    sudo mkdir -p "$mount_point"
    log_info "Created mount point: $mount_point"

    # Check if already mounted
    if mountpoint -q "$mount_point"; then
        log_info "NFS already mounted"
    else
        log_info "Mounting NFS from $nfs_export..."

        # Add to fstab if not present
        if ! grep -q "$nfs_export" /etc/fstab 2>/dev/null; then
            log_info "Adding to /etc/fstab..."
            echo "$nfs_export $mount_point nfs rw,hard,intr,noatime 0 0" | sudo tee -a /etc/fstab
        fi

        # Mount
        if sudo mount "$mount_point" 2>/dev/null; then
            log_info "NFS mounted successfully"
        else
            log_error "Failed to mount NFS. Check:"
            log_error "  1. Synology NFS service is enabled"
            log_error "  2. /volume1/frigate is exported"
            log_error "  3. This server's IP is allowed in NFS permissions"
            exit 1
        fi
    fi

    # Verify write access
    if touch "$mount_point/.write-test" 2>/dev/null; then
        rm "$mount_point/.write-test"
        log_info "✓ NFS writable"
    else
        log_error "NFS mounted but not writable"
        log_error "Check Synology NFS permissions for this server's IP"
        exit 1
    fi
}

# Create directory structure
setup_directories() {
    log_step "Creating directory structure..."

    mkdir -p frigate/config
    mkdir -p mosquitto/{config,data,log}
    mkdir -p double-take
    mkdir -p compreface/postgres
    mkdir -p platerecognizer
    mkdir -p whisper

    # Set permissions for mosquitto
    sudo chown -R 1883:1883 mosquitto/ 2>/dev/null || true

    log_info "✓ Directories created"
}

# Pull Docker images
pull_images() {
    log_step "Pulling Docker images (this may take 10-15 minutes)..."

    # Pull core services (not full profile)
    docker compose pull mqtt frigate compreface-postgres compreface-admin compreface-api compreface double-take

    log_info "✓ Images downloaded"
}

# Start services
start_services() {
    log_step "Starting services..."

    # Start MQTT first
    log_info "Starting MQTT broker..."
    docker compose up -d mqtt
    sleep 5

    # Verify MQTT
    if ! docker exec mqtt mosquitto_sub -t '$SYS/#' -C 1 -W 5 &>/dev/null; then
        log_error "MQTT failed to start properly"
        docker logs mqtt
        exit 1
    fi
    log_info "✓ MQTT broker running"

    # Start CompreFace database
    log_info "Starting CompreFace database..."
    docker compose up -d compreface-postgres
    sleep 10

    # Start CompreFace services
    log_info "Starting CompreFace services..."
    docker compose up -d compreface-admin compreface-api compreface
    sleep 15

    # Start Frigate
    log_info "Starting Frigate (may take several minutes on first run)..."
    log_warn "Frigate will compile TensorRT models - this is normal"
    docker compose up -d frigate

    # Wait for Frigate
    local attempts=0
    while ! curl -sf http://localhost:5000/api/version &>/dev/null; do
        attempts=$((attempts + 1))
        if [[ $attempts -gt 60 ]]; then
            log_error "Frigate failed to start after 10 minutes"
            log_error "Check logs: docker logs frigate"
            exit 1
        fi
        echo -n "."
        sleep 10
    done
    echo ""
    log_info "✓ Frigate running"

    # Start Double-Take
    log_info "Starting Double-Take..."
    docker compose up -d double-take
    sleep 10

    log_info "✓ All services started"
}

# Verify installation
verify() {
    log_step "Verifying installation..."

    local services=(mqtt frigate compreface double-take)
    local failed=0

    for service in "${services[@]}"; do
        if docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
            log_info "✓ $service running"
        else
            log_error "✗ $service not running"
            failed=1
        fi
    done

    # Test endpoints
    sleep 5

    if curl -sf http://localhost:5000/api/version &>/dev/null; then
        log_info "✓ Frigate UI accessible"
    else
        log_warn "✗ Frigate UI not accessible yet (may still be starting)"
    fi

    if curl -sf http://localhost:8000 &>/dev/null; then
        log_info "✓ CompreFace UI accessible"
    else
        log_warn "✗ CompreFace UI not accessible yet"
    fi

    if curl -sf http://localhost:3000 &>/dev/null; then
        log_info "✓ Double-Take UI accessible"
    else
        log_warn "✗ Double-Take UI not accessible yet"
    fi

    if [[ $failed -eq 0 ]]; then
        echo ""
        log_info "======================================"
        log_info "Installation complete!"
        log_info "======================================"
        echo ""
        echo "Next steps:"
        echo ""
        echo "1. Access Frigate: http://${HOST_IP}:5000"
        echo "   - Familiarize yourself with the UI"
        echo "   - Note: No cameras configured yet (waiting for hardware)"
        echo ""
        echo "2. Access CompreFace: http://${HOST_IP}:8000"
        echo "   - Create an account (local only)"
        echo "   - Create a 'Recognition' service"
        echo "   - Copy the API key to .env as COMPREFACE_API_KEY"
        echo "   - Then restart: docker compose restart double-take"
        echo ""
        echo "3. Access Double-Take: http://${HOST_IP}:3000"
        echo "   - After CompreFace API key is set"
        echo "   - Train faces via the UI"
        echo ""
        echo "4. When camera arrives tomorrow:"
        echo "   - Test camera: ./scripts/test-camera.sh <camera-ip> admin <password>"
        echo "   - Uncomment camera config in frigate/config/config.yml"
        echo "   - Update .env with DOORBELL_IP"
        echo "   - Restart: make restart-frigate"
        echo ""
        echo "5. Set up health monitoring:"
        echo "   - Test health check: ./scripts/health-check.sh"
        echo "   - Add to cron: sudo cp scripts/security-stack.cron /etc/cron.d/"
        echo ""
    else
        log_error "Some services failed to start"
        log_error "Check logs: docker compose logs"
        exit 1
    fi
}

# Main
main() {
    echo "======================================"
    echo "Home Security Stack Setup"
    echo "======================================"
    echo ""

    check_prerequisites
    setup_env
    setup_nfs
    setup_directories
    pull_images
    start_services
    verify
}

main "$@"
