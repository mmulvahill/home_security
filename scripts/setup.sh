#!/bin/bash
# Home Security Stack - Idempotent Setup & Deploy
# Safe to run repeatedly. Checks current state before each action.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
cd "$PROJECT_DIR"

# --- Prerequisites ---
ensure_prerequisites() {
    log_step "Checking prerequisites..."

    require_commands docker curl jq nc || exit 1

    if ! docker compose version &>/dev/null; then
        log_error "Docker Compose v2 not available"
        exit 1
    fi
    log_info "Docker: $(docker --version | cut -d' ' -f3)"
    log_info "Compose: $(docker compose version --short)"

    if ! docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi &>/dev/null; then
        log_error "NVIDIA GPU not accessible through Docker"
        log_error "Install: sudo apt install nvidia-container-toolkit"
        exit 1
    fi
    log_info "GPU access OK"

    if ! command -v mount.nfs &>/dev/null; then
        log_error "NFS client not installed. Run: sudo apt-get install -y nfs-common"
        exit 1
    fi
}

# --- Environment ---
ensure_env() {
    log_step "Validating environment..."
    load_env
    require_env FRIGATE_RTSP_PASSWORD DOORBELL_IP HOST_IP SYNOLOGY_IP SYNOLOGY_NFS_EXPORT
    log_info "Environment OK"
}

# --- NFS ---
ensure_nfs() {
    log_step "Ensuring NFS mount..."
    load_env

    local mount_point="${NFS_FRIGATE_PATH:-/mnt/synology/frigate}"
    local nfs_source="${SYNOLOGY_IP}:${SYNOLOGY_NFS_EXPORT}"

    if mountpoint -q "$mount_point" 2>/dev/null; then
        log_info "Already mounted at $mount_point"
    else
        # Create mount point if needed
        [[ -d "$mount_point" ]] || sudo mkdir -p "$mount_point"

        # Add to fstab if not already present
        if ! grep -qF "$nfs_source" /etc/fstab 2>/dev/null; then
            log_info "Adding fstab entry for $nfs_source"
            echo "${nfs_source} ${mount_point} nfs rw,hard,intr,noatime 0 0" | sudo tee -a /etc/fstab >/dev/null
        fi

        log_info "Mounting $nfs_source -> $mount_point"
        if ! sudo mount "$mount_point"; then
            log_error "NFS mount failed. Verify on Synology:"
            log_error "  1. NFS service enabled (Control Panel -> File Services -> NFS)"
            log_error "  2. Shared folder has NFS permission for ${HOST_IP}"
            log_error "  3. Export path matches: showmount -e ${SYNOLOGY_IP}"
            exit 1
        fi
    fi

    # Verify write access (Docker runs as root, so sudo fallback is fine)
    if touch "$mount_point/.write-test" 2>/dev/null; then
        rm "$mount_point/.write-test"
        log_info "NFS writable"
    elif sudo touch "$mount_point/.write-test" 2>/dev/null; then
        sudo rm "$mount_point/.write-test"
        log_warn "NFS writable as root only (OK for Docker, but consider Squash='No mapping' on Synology)"
    else
        log_error "NFS mounted but not writable. Check Synology NFS permissions."
        exit 1
    fi
}

# --- Directories ---
ensure_directories() {
    log_step "Ensuring directory structure..."

    local dirs=(
        frigate/config
        mosquitto/config mosquitto/data mosquitto/log
    )
    for d in "${dirs[@]}"; do
        mkdir -p "$d"
    done

    # Mosquitto needs specific ownership
    sudo chown -R 1883:1883 mosquitto/ 2>/dev/null || true

    log_info "Directories OK"
}

# --- Images ---
ensure_images() {
    log_step "Pulling Docker images (may take a while on first run)..."
    docker compose pull mqtt frigate
    log_info "Images up to date"
}

# --- Services ---
deploy_services() {
    log_step "Deploying services..."

    local services=(mqtt frigate)
    docker compose up -d "${services[@]}"

    # Wait for Frigate (slowest service - TensorRT model compilation on first run)
    log_info "Waiting for Frigate to become healthy..."
    local attempts=0
    while ! curl -sf http://localhost:5000/api/version &>/dev/null; do
        attempts=$((attempts + 1))
        if [[ $attempts -gt 60 ]]; then
            log_error "Frigate not healthy after 10 minutes. Check: docker logs frigate"
            exit 1
        fi
        echo -n "."
        sleep 10
    done
    echo ""
    log_info "All services deployed"
}

# --- Verify ---
verify() {
    log_step "Verifying deployment..."
    load_env

    local all_ok=true
    for svc in mqtt frigate; do
        if docker ps --format '{{.Names}}' | grep -q "^${svc}$"; then
            log_info "$svc running"
        else
            log_error "$svc not running"
            all_ok=false
        fi
    done

    local endpoints=(
        "Frigate|http://localhost:5000/api/version"
    )
    for entry in "${endpoints[@]}"; do
        local name="${entry%%|*}" url="${entry#*|}"
        if curl -sf "$url" &>/dev/null; then
            log_info "$name reachable"
        else
            log_warn "$name not reachable yet (may still be starting)"
        fi
    done

    if $all_ok; then
        echo ""
        log_info "======================================"
        log_info "Deployment complete!"
        log_info "======================================"
        echo ""
        echo "Frigate:     http://${HOST_IP}:5000"
        echo ""
    else
        log_error "Some services failed. Check: docker compose logs"
        exit 1
    fi
}

# --- Main ---
main() {
    echo "======================================"
    echo "Home Security Stack - Deploy"
    echo "======================================"
    echo ""

    ensure_prerequisites
    ensure_env
    ensure_nfs
    ensure_directories
    ensure_images
    deploy_services
    verify
}

main "$@"
