# Home Security AI System - Implementation Specification

**Version:** 1.0  
**Date:** January 19, 2025  
**Author:** Matt (with Claude assistance)  
**Target:** Claude Code implementation  

---

## Executive Summary

This specification defines a local-first, AI-powered home security camera system built on commodity hardware. The system prioritizes privacy, reliability during network outages, and low maintenance overhead. It leverages an existing GPU server (3x NVIDIA 3090) for advanced AI inference including object detection, face recognition, license plate recognition, and speech-to-text.

---

## 1. System Architecture

### 1.1 Hardware Inventory

| Component | Specs | Role |
|-----------|-------|------|
| GPU Server | AMD Epyc 128-thread, 512GB RAM, 3x NVIDIA 3090 24GB, Kubuntu | AI inference, Frigate NVR |
| Synology DS1522+ | AMD Ryzen R1600, ~12TB storage | Home Assistant, NFS storage |
| UniFi Dream Machine Pro | Basement | Primary router/firewall |
| Asus ZenWiFi AX | Mesh to garage | WiFi coverage |

### 1.2 Network Topology

```
Internet
    │
    ▼
┌─────────────┐
│   UDM Pro   │ (Basement)
│ 10.x.x.1    │
└──────┬──────┘
       │
       ├──── MoCA Bridge ──── Office Switch (25-port, 10GbE)
       │                           │
       │                      ┌────┴────┐
       │                      │ Devices │
       │                      └─────────┘
       │
       ├──── Synology DS1522+ (static IP: TBD)
       │         └── Home Assistant
       │         └── NFS exports
       │
       ├──── GPU Server (static IP: TBD, Tailscale VPN)
       │         └── Frigate + AI Stack
       │
       └──── Asus ZenWiFi Mesh
                  │
                  └── Garage AP
                        └── Future cameras
```

### 1.3 Software Stack

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    GPU SERVER (Docker Compose Stack)                     │
│                                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐ │
│  │   Frigate    │  │ Double-Take  │  │    Plate     │  │   Whisper   │ │
│  │  (GPU 0)     │  │              │  │  Recognizer  │  │   (GPU 1)   │ │
│  │              │  │              │  │              │  │             │ │
│  │ • TensorRT   │  │ • Face match │  │ • ALPR       │  │ • STT       │ │
│  │ • Recording  │  │ • Training   │  │ • Plate log  │  │ • Audio     │ │
│  │ • Detection  │  │ • Alerts     │  │              │  │   events    │ │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬──────┘ │
│         │                 │                 │                 │        │
│         └─────────────────┴─────────────────┴─────────────────┘        │
│                                    │                                    │
│                          ┌────────┴────────┐                           │
│                          │   MQTT Broker   │                           │
│                          │  (Mosquitto)    │                           │
│                          └────────┬────────┘                           │
│                                   │                                     │
└───────────────────────────────────┼─────────────────────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    │      Synology DS1522+         │
                    │  ┌─────────────────────────┐  │
                    │  │    Home Assistant       │  │
                    │  │  • Automations          │  │
                    │  │  • Notifications        │  │
                    │  │  • Dashboard            │  │
                    │  └─────────────────────────┘  │
                    │  ┌─────────────────────────┐  │
                    │  │    NFS Storage          │  │
                    │  │  • /volume1/frigate     │  │
                    │  └─────────────────────────┘  │
                    └───────────────────────────────┘
```

---

## 2. Implementation Requirements

### 2.1 Core Principles

1. **Local-first**: All critical functionality must work without internet
2. **Minimal maintenance**: Self-healing, automatic updates where safe, alerting on failures
3. **Single source of truth**: One docker-compose.yml, one config repo
4. **Idempotent deployment**: Running setup twice should be safe
5. **Graceful degradation**: Individual service failures shouldn't cascade

### 2.2 Directory Structure

```
/opt/security-stack/
├── docker-compose.yml          # Main orchestration
├── .env                        # Secrets (gitignored)
├── .env.example                # Template for secrets
├── README.md                   # Operational runbook
├── Makefile                    # Common operations
├── scripts/
│   ├── setup.sh               # Initial setup script
│   ├── backup.sh              # Backup configurations
│   ├── health-check.sh        # System health verification
│   └── update.sh              # Safe update procedure
├── frigate/
│   └── config/
│       └── config.yml         # Frigate configuration
├── mosquitto/
│   ├── config/
│   │   └── mosquitto.conf
│   ├── data/
│   └── log/
├── double-take/
│   └── config.yml
├── platerecognizer/
│   └── config/
└── whisper/
    └── config/
```

### 2.3 Technology Choices

| Component | Technology | Rationale |
|-----------|------------|-----------|
| Container Runtime | Docker + Docker Compose v2 | Standard, well-supported |
| Object Detection | Frigate + TensorRT | GPU-accelerated, mature |
| Face Recognition | CompreFace + Double-Take | Open source, local |
| ALPR | Plate Recognizer (local) or CodeProject.AI | Accuracy vs cost tradeoff |
| Speech-to-Text | Whisper (faster-whisper) | Open source, GPU-accelerated |
| Message Bus | Mosquitto MQTT | Lightweight, standard |
| Storage | NFS to Synology | Centralized, RAID-protected |
| Automation | Home Assistant | Already deployed |

---

## 3. Detailed Component Specifications

### 3.1 Frigate NVR

**Image**: `ghcr.io/blakeblackshear/frigate:stable-tensorrt`

**Resource Allocation**:
- GPU: Device 0 (first 3090)
- Shared Memory: 512MB minimum
- CPU: No limit (Epyc has headroom)

**Configuration Requirements**:

```yaml
# /opt/security-stack/frigate/config/config.yml

mqtt:
  enabled: true
  host: mqtt  # Docker service name
  port: 1883
  topic_prefix: frigate
  client_id: frigate
  stats_interval: 60

detectors:
  tensorrt:
    type: tensorrt
    device: 0

model:
  path: /config/model_cache/tensorrt/yolov7-320.trt
  input_tensor: nchw
  input_pixel_format: rgb
  width: 320
  height: 320

database:
  path: /config/frigate.db

ffmpeg:
  hwaccel_args: preset-nvidia-h264
  output_args:
    record: preset-record-generic-audio-aac

go2rtc:
  streams:
    front_door:
      - "rtsp://admin:${FRIGATE_RTSP_PASSWORD}@${DOORBELL_IP}:554/h264Preview_01_main"
  webrtc:
    candidates:
      - ${HOST_IP}:8555
      - stun:8555

record:
  enabled: true
  retain:
    days: 14
    mode: motion
  events:
    pre_capture: 5
    post_capture: 10
    retain:
      default: 60
      mode: active_objects

snapshots:
  enabled: true
  clean_copy: true
  timestamp: true
  bounding_box: true
  retain:
    default: 60

objects:
  track:
    - person
    - car
    - motorcycle
    - bicycle
    - dog
    - cat
    - package
  filters:
    person:
      min_area: 5000
      max_area: 100000
      threshold: 0.7
    car:
      min_area: 10000
      threshold: 0.7

audio:
  enabled: true
  listen:
    - bark
    - fire_alarm
    - glass_breaking
    - scream
    - speech
    - yell

# Camera definitions - start with doorbell only
cameras:
  front_door:
    enabled: true
    ffmpeg:
      inputs:
        - path: rtsp://admin:${FRIGATE_RTSP_PASSWORD}@${DOORBELL_IP}:554/h264Preview_01_sub
          roles:
            - detect
            - audio
        - path: rtsp://admin:${FRIGATE_RTSP_PASSWORD}@${DOORBELL_IP}:554/h264Preview_01_main
          roles:
            - record
    detect:
      enabled: true
      width: 640
      height: 480
      fps: 10
    audio:
      enabled: true
    objects:
      track:
        - person
        - package
      filters:
        person:
          min_score: 0.6
          threshold: 0.7
    zones:
      porch:
        coordinates: 0,480,640,480,640,200,0,200
        objects:
          - person
          - package
    snapshots:
      enabled: true
      bounding_box: true
    mqtt:
      enabled: true
      timestamp: true
      bounding_box: true
      crop: true
```

**Validation Criteria**:
- [ ] TensorRT model compiles successfully on first run
- [ ] RTSP streams connect within 30 seconds
- [ ] Detection events publish to MQTT
- [ ] Recordings save to NFS mount
- [ ] Web UI accessible on port 5000

### 3.2 MQTT Broker (Mosquitto)

**Image**: `eclipse-mosquitto:2`

**Configuration**:

```conf
# /opt/security-stack/mosquitto/config/mosquitto.conf

# Listeners
listener 1883
listener 9001
protocol websockets

# Persistence
persistence true
persistence_location /mosquitto/data/

# Logging
log_dest file /mosquitto/log/mosquitto.log
log_dest stdout
log_type error
log_type warning
log_type notice
log_type information
connection_messages true
log_timestamp true

# Security - initial setup (update for production)
allow_anonymous true

# Production security (uncomment after initial setup):
# password_file /mosquitto/config/passwd
# allow_anonymous false
# acl_file /mosquitto/config/acl
```

**Validation Criteria**:
- [ ] Port 1883 accepts connections
- [ ] Port 9001 (websocket) accepts connections
- [ ] Messages persist across container restart
- [ ] Frigate successfully connects

### 3.3 Face Recognition Stack

#### 3.3.1 CompreFace

**Images**:
- `postgres:11.5` - Database
- `exadel/compreface-admin:latest` - Admin service
- `exadel/compreface-api:latest` - Recognition API  
- `exadel/compreface-fe:latest` - Web UI

**Configuration**:
- Web UI on port 8000
- Create "Recognition" service via UI after first boot
- API key stored in `.env` as `COMPREFACE_API_KEY`

#### 3.3.2 Double-Take

**Image**: `jakowenko/double-take:latest`

**Configuration**:

```yaml
# /opt/security-stack/double-take/config.yml

mqtt:
  host: mqtt
  port: 1883
  topic: double-take

frigate:
  url: http://frigate:5000
  topic: frigate/events

detectors:
  compreface:
    url: http://compreface-api:8080
    key: ${COMPREFACE_API_KEY}
    det_prob_threshold: 0.8
    face_plugins: landmarks,gender,age
    status_codes:
      - 200
      - 404

detect:
  match:
    save: true
    base64: false
    min_area: 10000
  unknown:
    save: true

time:
  timezone: America/Chicago

cameras:
  front_door:
    zones:
      - camera: front_door
```

**Validation Criteria**:
- [ ] CompreFace web UI accessible on port 8000
- [ ] API key generated and stored
- [ ] Double-Take connects to Frigate events
- [ ] Face detection produces match/unknown events
- [ ] Training UI functional

### 3.4 License Plate Recognition

**Option A: Plate Recognizer Local** (Recommended for privacy)

**Image**: `platerecognizer/alpr:latest`

```yaml
# In docker-compose.yml
platerecognizer:
  image: platerecognizer/alpr:latest
  container_name: platerecognizer
  restart: unless-stopped
  ports:
    - "8001:8080"
  environment:
    - LICENSE_KEY=${PLATE_RECOGNIZER_KEY}
    - TOKEN=${PLATE_RECOGNIZER_TOKEN}
  volumes:
    - ./platerecognizer:/user-data
```

**Note**: Requires license purchase (~$50-100 one-time) for local. Free tier (2500/month) uses cloud.

**Option B: CodeProject.AI** (Free, open source)

```yaml
codeproject-ai:
  image: codeproject/ai-server:cuda12_2
  container_name: codeproject-ai
  restart: unless-stopped
  deploy:
    resources:
      reservations:
        devices:
          - driver: nvidia
            device_ids: ['2']
            capabilities: [gpu]
  ports:
    - "32168:32168"
  volumes:
    - ./codeproject-ai:/etc/codeproject/ai
  environment:
    - CUDA_VISIBLE_DEVICES=2
```

**Integration**: Custom Python service subscribes to Frigate `car` events in garage_zoom zone, sends snapshot to ALPR, logs results.

### 3.5 Speech-to-Text (Whisper)

**Image**: `onerahmet/openai-whisper-asr-webservice:latest-gpu`

```yaml
whisper:
  image: onerahmet/openai-whisper-asr-webservice:latest-gpu
  container_name: whisper
  restart: unless-stopped
  deploy:
    resources:
      reservations:
        devices:
          - driver: nvidia
            device_ids: ['1']
            capabilities: [gpu]
  ports:
    - "9000:9000"
  environment:
    - ASR_MODEL=medium
    - ASR_ENGINE=faster_whisper
```

**Integration**: Future - extract audio from doorbell events, transcribe, log/alert on keywords.

---

## 4. Docker Compose Master File

```yaml
# /opt/security-stack/docker-compose.yml
version: "3.9"

services:
  # ============================================
  # MQTT BROKER - Central message bus
  # ============================================
  mqtt:
    image: eclipse-mosquitto:2
    container_name: mqtt
    restart: unless-stopped
    volumes:
      - ./mosquitto/config:/mosquitto/config:ro
      - ./mosquitto/data:/mosquitto/data
      - ./mosquitto/log:/mosquitto/log
    ports:
      - "1883:1883"
      - "9001:9001"
    healthcheck:
      test: ["CMD", "mosquitto_sub", "-t", "$$SYS/#", "-C", "1", "-i", "healthcheck", "-W", "3"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s

  # ============================================
  # FRIGATE - NVR with GPU object detection
  # ============================================
  frigate:
    image: ghcr.io/blakeblackshear/frigate:stable-tensorrt
    container_name: frigate
    restart: unless-stopped
    privileged: true
    shm_size: "512mb"
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              device_ids: ['0']
              capabilities: [gpu, video, compute]
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - ./frigate/config:/config
      - ${NFS_FRIGATE_PATH:-/mnt/synology/frigate}/recordings:/media/frigate/recordings
      - ${NFS_FRIGATE_PATH:-/mnt/synology/frigate}/clips:/media/frigate/clips
      - type: tmpfs
        target: /tmp/cache
        tmpfs:
          size: 1000000000
    ports:
      - "5000:5000"
      - "8554:8554"
      - "8555:8555/tcp"
      - "8555:8555/udp"
    environment:
      - FRIGATE_RTSP_PASSWORD=${FRIGATE_RTSP_PASSWORD}
      - NVIDIA_VISIBLE_DEVICES=0
      - NVIDIA_DRIVER_CAPABILITIES=compute,video,utility
    depends_on:
      mqtt:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/api/version"]
      interval: 60s
      timeout: 10s
      retries: 3
      start_period: 120s

  # ============================================
  # COMPREFACE - Face recognition backend
  # ============================================
  compreface-postgres:
    image: postgres:11.5
    container_name: compreface-postgres
    restart: unless-stopped
    environment:
      - POSTGRES_USER=compreface
      - POSTGRES_PASSWORD=${COMPREFACE_DB_PASSWORD:-compreface}
      - POSTGRES_DB=compreface
    volumes:
      - ./compreface/postgres:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U compreface"]
      interval: 10s
      timeout: 5s
      retries: 5

  compreface-admin:
    image: exadel/compreface-admin:latest
    container_name: compreface-admin
    restart: unless-stopped
    environment:
      - POSTGRES_USER=compreface
      - POSTGRES_PASSWORD=${COMPREFACE_DB_PASSWORD:-compreface}
      - POSTGRES_URL=jdbc:postgresql://compreface-postgres:5432/compreface
      - SPRING_PROFILES_ACTIVE=dev
      - ENABLE_EMAIL_SERVER=false
      - ADMIN_JAVA_OPTS=-Xmx1g
    depends_on:
      compreface-postgres:
        condition: service_healthy

  compreface-api:
    image: exadel/compreface-api:latest
    container_name: compreface-api
    restart: unless-stopped
    environment:
      - POSTGRES_USER=compreface
      - POSTGRES_PASSWORD=${COMPREFACE_DB_PASSWORD:-compreface}
      - POSTGRES_URL=jdbc:postgresql://compreface-postgres:5432/compreface
      - SPRING_PROFILES_ACTIVE=dev
      - API_JAVA_OPTS=-Xmx2g
      - SAVE_IMAGES_TO_DB=true
    depends_on:
      compreface-postgres:
        condition: service_healthy

  compreface:
    image: exadel/compreface-fe:latest
    container_name: compreface
    restart: unless-stopped
    ports:
      - "8000:80"
    depends_on:
      - compreface-admin
      - compreface-api
    environment:
      - CLIENT_MAX_BODY_SIZE=10M

  # ============================================
  # DOUBLE-TAKE - Face recognition coordinator
  # ============================================
  double-take:
    image: jakowenko/double-take:latest
    container_name: double-take
    restart: unless-stopped
    volumes:
      - ./double-take:/.storage
    ports:
      - "3000:3000"
    environment:
      - TZ=America/Chicago
    depends_on:
      - mqtt
      - frigate
      - compreface

  # ============================================
  # WHISPER - Speech-to-text (GPU 1)
  # ============================================
  whisper:
    image: onerahmet/openai-whisper-asr-webservice:latest-gpu
    container_name: whisper
    restart: unless-stopped
    profiles:
      - full  # Only starts with --profile full
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              device_ids: ['1']
              capabilities: [gpu]
    ports:
      - "9000:9000"
    environment:
      - ASR_MODEL=medium
      - ASR_ENGINE=faster_whisper

  # ============================================
  # PLATE RECOGNIZER - ALPR (optional)
  # ============================================
  platerecognizer:
    image: platerecognizer/alpr:latest
    container_name: platerecognizer
    restart: unless-stopped
    profiles:
      - full  # Only starts with --profile full
    ports:
      - "8001:8080"
    environment:
      - LICENSE_KEY=${PLATE_RECOGNIZER_KEY:-}
    volumes:
      - ./platerecognizer:/user-data

networks:
  default:
    name: security-stack
    driver: bridge
```

---

## 5. Setup Scripts

### 5.1 Initial Setup Script

```bash
#!/bin/bash
# /opt/security-stack/scripts/setup.sh
# Initial setup for security stack

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker not installed"
        exit 1
    fi
    
    # Docker Compose v2
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose v2 not available"
        exit 1
    fi
    
    # NVIDIA Container Toolkit
    if ! docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi &> /dev/null; then
        log_error "NVIDIA Container Toolkit not working"
        exit 1
    fi
    
    # NFS client
    if ! command -v mount.nfs &> /dev/null; then
        log_warn "NFS client not installed - installing..."
        sudo apt-get update && sudo apt-get install -y nfs-common
    fi
    
    log_info "Prerequisites OK"
}

# Setup environment file
setup_env() {
    log_info "Setting up environment..."
    
    if [[ ! -f .env ]]; then
        if [[ -f .env.example ]]; then
            cp .env.example .env
            log_warn "Created .env from template - EDIT THIS FILE with your values"
            log_warn "Required: FRIGATE_RTSP_PASSWORD, DOORBELL_IP, HOST_IP, SYNOLOGY_IP"
            exit 1
        else
            log_error ".env.example not found"
            exit 1
        fi
    fi
    
    # Validate required variables
    source .env
    local required_vars=(FRIGATE_RTSP_PASSWORD DOORBELL_IP HOST_IP SYNOLOGY_IP)
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Missing required variable: $var"
            exit 1
        fi
    done
    
    log_info "Environment OK"
}

# Setup NFS mount
setup_nfs() {
    log_info "Setting up NFS mount..."
    
    local mount_point="/mnt/synology/frigate"
    local nfs_export="${SYNOLOGY_IP}:/volume1/frigate"
    
    # Create mount point
    sudo mkdir -p "$mount_point"
    
    # Check if already mounted
    if mountpoint -q "$mount_point"; then
        log_info "NFS already mounted"
        return
    fi
    
    # Add to fstab if not present
    if ! grep -q "$nfs_export" /etc/fstab; then
        echo "$nfs_export $mount_point nfs rw,hard,intr,noatime 0 0" | sudo tee -a /etc/fstab
    fi
    
    # Mount
    sudo mount "$mount_point"
    
    # Verify write access
    if touch "$mount_point/.write-test" 2>/dev/null; then
        rm "$mount_point/.write-test"
        log_info "NFS mount OK with write access"
    else
        log_error "NFS mount exists but not writable"
        exit 1
    fi
}

# Create directory structure
setup_directories() {
    log_info "Creating directory structure..."
    
    mkdir -p frigate/config
    mkdir -p mosquitto/{config,data,log}
    mkdir -p double-take
    mkdir -p compreface/postgres
    mkdir -p platerecognizer
    mkdir -p whisper
    
    # Set permissions for mosquitto
    sudo chown -R 1883:1883 mosquitto/
    
    log_info "Directories OK"
}

# Generate configurations
generate_configs() {
    log_info "Generating configurations..."
    
    # Mosquitto config
    if [[ ! -f mosquitto/config/mosquitto.conf ]]; then
        cat > mosquitto/config/mosquitto.conf << 'EOF'
listener 1883
listener 9001
protocol websockets
persistence true
persistence_location /mosquitto/data/
log_dest file /mosquitto/log/mosquitto.log
log_dest stdout
log_type error
log_type warning
log_type notice
connection_messages true
log_timestamp true
allow_anonymous true
EOF
    fi
    
    log_info "Configurations OK"
}

# Pull images
pull_images() {
    log_info "Pulling Docker images (this may take a while)..."
    docker compose pull
    log_info "Images OK"
}

# Start services
start_services() {
    log_info "Starting services..."
    
    # Start core services first
    docker compose up -d mqtt
    sleep 5
    
    # Verify MQTT
    if ! docker exec mqtt mosquitto_sub -t '$SYS/#' -C 1 -W 5; then
        log_error "MQTT failed to start properly"
        exit 1
    fi
    
    # Start Frigate
    docker compose up -d frigate
    
    # Wait for Frigate (TensorRT compilation takes time on first run)
    log_info "Waiting for Frigate to initialize (may take several minutes on first run)..."
    local attempts=0
    while ! curl -sf http://localhost:5000/api/version &>/dev/null; do
        attempts=$((attempts + 1))
        if [[ $attempts -gt 60 ]]; then
            log_error "Frigate failed to start - check logs: docker logs frigate"
            exit 1
        fi
        sleep 10
    done
    
    # Start face recognition stack
    docker compose up -d compreface-postgres
    sleep 10
    docker compose up -d compreface-admin compreface-api compreface double-take
    
    log_info "Services started"
}

# Verify installation
verify() {
    log_info "Verifying installation..."
    
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
    local endpoints=(
        "http://localhost:5000|Frigate"
        "http://localhost:8000|CompreFace"
        "http://localhost:3000|Double-Take"
    )
    
    for endpoint in "${endpoints[@]}"; do
        IFS='|' read -r url name <<< "$endpoint"
        if curl -sf "$url" &>/dev/null; then
            log_info "✓ $name UI accessible"
        else
            log_warn "✗ $name UI not accessible yet"
        fi
    done
    
    if [[ $failed -eq 0 ]]; then
        log_info "Installation complete!"
        echo ""
        echo "Next steps:"
        echo "1. Access Frigate: http://${HOST_IP}:5000"
        echo "2. Access CompreFace: http://${HOST_IP}:8000"
        echo "3. Access Double-Take: http://${HOST_IP}:3000"
        echo "4. Configure Home Assistant MQTT integration"
        echo ""
    else
        log_error "Some services failed to start"
        exit 1
    fi
}

# Main
main() {
    echo "======================================"
    echo "Security Stack Setup"
    echo "======================================"
    
    check_prerequisites
    setup_env
    setup_nfs
    setup_directories
    generate_configs
    pull_images
    start_services
    verify
}

main "$@"
```

### 5.2 Health Check Script

```bash
#!/bin/bash
# /opt/security-stack/scripts/health-check.sh
# Health check for security stack - run via cron

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

source .env

ALERT_FILE="/tmp/security-stack-alerts"
MQTT_TOPIC="security-stack/health"

log_alert() {
    local message="$1"
    echo "$(date -Iseconds) $message" >> "$ALERT_FILE"
    # Publish to MQTT for Home Assistant
    mosquitto_pub -h localhost -t "$MQTT_TOPIC" -m "{\"status\":\"alert\",\"message\":\"$message\"}" 2>/dev/null || true
}

check_service() {
    local name="$1"
    if ! docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
        log_alert "Service $name is not running"
        return 1
    fi
    
    # Check if restarting
    local restart_count=$(docker inspect "$name" --format '{{.RestartCount}}' 2>/dev/null || echo "0")
    if [[ "$restart_count" -gt 5 ]]; then
        log_alert "Service $name has restarted $restart_count times"
    fi
    
    return 0
}

check_disk_space() {
    local mount_point="/mnt/synology/frigate"
    local threshold=90
    
    local usage=$(df "$mount_point" | awk 'NR==2 {print int($5)}')
    if [[ "$usage" -gt "$threshold" ]]; then
        log_alert "Disk usage on $mount_point is ${usage}%"
    fi
}

check_camera_connection() {
    # Check if Frigate can see the camera
    local camera_status=$(curl -sf "http://localhost:5000/api/front_door" | jq -r '.camera.camera_fps // 0')
    if [[ "$camera_status" == "0" ]]; then
        log_alert "Camera front_door appears disconnected"
    fi
}

check_gpu() {
    if ! nvidia-smi &>/dev/null; then
        log_alert "GPU not responding to nvidia-smi"
        return 1
    fi
    
    # Check GPU memory usage
    local gpu_mem=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits -i 0)
    if [[ "$gpu_mem" -gt 20000 ]]; then
        log_alert "GPU 0 memory usage high: ${gpu_mem}MB"
    fi
}

main() {
    # Clear previous alerts
    > "$ALERT_FILE"
    
    check_service "mqtt" || docker compose up -d mqtt
    check_service "frigate" || docker compose up -d frigate
    check_service "compreface" || docker compose up -d compreface
    check_service "double-take" || docker compose up -d double-take
    
    check_disk_space
    check_camera_connection
    check_gpu
    
    # If no alerts, publish healthy status
    if [[ ! -s "$ALERT_FILE" ]]; then
        mosquitto_pub -h localhost -t "$MQTT_TOPIC" -m '{"status":"healthy"}' 2>/dev/null || true
    fi
}

main "$@"
```

### 5.3 Makefile for Operations

```makefile
# /opt/security-stack/Makefile

.PHONY: help setup start stop restart logs status update backup health

COMPOSE = docker compose
SERVICES = mqtt frigate compreface-postgres compreface-admin compreface-api compreface double-take

help:
	@echo "Security Stack Operations"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  setup    - Initial setup (run once)"
	@echo "  start    - Start all services"
	@echo "  stop     - Stop all services"
	@echo "  restart  - Restart all services"
	@echo "  logs     - Tail logs for all services"
	@echo "  status   - Show service status"
	@echo "  update   - Pull latest images and restart"
	@echo "  backup   - Backup configurations"
	@echo "  health   - Run health check"
	@echo ""
	@echo "Service-specific:"
	@echo "  logs-frigate    - Tail Frigate logs"
	@echo "  restart-frigate - Restart Frigate only"
	@echo ""

setup:
	./scripts/setup.sh

start:
	$(COMPOSE) up -d $(SERVICES)

stop:
	$(COMPOSE) down

restart:
	$(COMPOSE) restart $(SERVICES)

logs:
	$(COMPOSE) logs -f --tail=100

logs-%:
	$(COMPOSE) logs -f --tail=100 $*

restart-%:
	$(COMPOSE) restart $*

status:
	$(COMPOSE) ps
	@echo ""
	@echo "Endpoints:"
	@echo "  Frigate:     http://localhost:5000"
	@echo "  CompreFace:  http://localhost:8000"
	@echo "  Double-Take: http://localhost:3000"

update:
	$(COMPOSE) pull
	$(COMPOSE) up -d $(SERVICES)

backup:
	./scripts/backup.sh

health:
	./scripts/health-check.sh

# GPU monitoring
gpu:
	watch -n 1 nvidia-smi

# Shell into container
shell-%:
	docker exec -it $* /bin/bash
```

---

## 6. Testing Requirements

### 6.1 Unit Tests (Pre-deployment)

```bash
#!/bin/bash
# /opt/security-stack/scripts/test-pre-deploy.sh

set -euo pipefail

echo "Running pre-deployment tests..."

# Test 1: Docker connectivity
echo -n "Docker daemon... "
docker info &>/dev/null && echo "OK" || { echo "FAIL"; exit 1; }

# Test 2: GPU access
echo -n "GPU access... "
docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi &>/dev/null && echo "OK" || { echo "FAIL"; exit 1; }

# Test 3: NFS mount
echo -n "NFS mount... "
mountpoint -q /mnt/synology/frigate && echo "OK" || { echo "FAIL"; exit 1; }

# Test 4: NFS writable
echo -n "NFS writable... "
touch /mnt/synology/frigate/.test && rm /mnt/synology/frigate/.test && echo "OK" || { echo "FAIL"; exit 1; }

# Test 5: Environment variables
echo -n "Environment... "
source .env
[[ -n "${FRIGATE_RTSP_PASSWORD:-}" ]] && echo "OK" || { echo "FAIL"; exit 1; }

# Test 6: Config syntax (YAML)
echo -n "Frigate config syntax... "
python3 -c "import yaml; yaml.safe_load(open('frigate/config/config.yml'))" && echo "OK" || { echo "FAIL"; exit 1; }

# Test 7: Docker Compose syntax
echo -n "Docker Compose syntax... "
docker compose config &>/dev/null && echo "OK" || { echo "FAIL"; exit 1; }

echo ""
echo "All pre-deployment tests passed!"
```

### 6.2 Integration Tests (Post-deployment)

```bash
#!/bin/bash
# /opt/security-stack/scripts/test-post-deploy.sh

set -euo pipefail

echo "Running post-deployment tests..."

# Test 1: MQTT connectivity
echo -n "MQTT broker... "
timeout 5 mosquitto_sub -h localhost -t '$SYS/broker/uptime' -C 1 &>/dev/null && echo "OK" || { echo "FAIL"; exit 1; }

# Test 2: Frigate API
echo -n "Frigate API... "
curl -sf http://localhost:5000/api/version &>/dev/null && echo "OK" || { echo "FAIL"; exit 1; }

# Test 3: Frigate camera status (may take time)
echo -n "Frigate camera... "
sleep 5
CAMERA_STATUS=$(curl -sf http://localhost:5000/api/front_door 2>/dev/null | jq -r '.camera.camera_fps // 0')
[[ "$CAMERA_STATUS" != "0" ]] && echo "OK (${CAMERA_STATUS} fps)" || echo "WARN (no camera connected)"

# Test 4: CompreFace API
echo -n "CompreFace API... "
curl -sf http://localhost:8000 &>/dev/null && echo "OK" || { echo "FAIL"; exit 1; }

# Test 5: Double-Take API
echo -n "Double-Take API... "
curl -sf http://localhost:3000/api/status &>/dev/null && echo "OK" || { echo "FAIL"; exit 1; }

# Test 6: MQTT message flow (Frigate → MQTT)
echo -n "MQTT message flow... "
timeout 30 mosquitto_sub -h localhost -t 'frigate/available' -C 1 &>/dev/null && echo "OK" || echo "WARN (no message in 30s)"

# Test 7: GPU utilization
echo -n "GPU utilization... "
GPU_UTIL=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits -i 0)
echo "OK (${GPU_UTIL}%)"

# Test 8: Recording storage
echo -n "Recording storage... "
STORAGE=$(df -h /mnt/synology/frigate | awk 'NR==2 {print $4}')
echo "OK (${STORAGE} available)"

echo ""
echo "Post-deployment tests complete!"
```

### 6.3 Camera Integration Test

```bash
#!/bin/bash
# /opt/security-stack/scripts/test-camera.sh
# Test camera RTSP connectivity before adding to Frigate

CAMERA_IP="${1:-}"
CAMERA_USER="${2:-admin}"
CAMERA_PASS="${3:-}"

if [[ -z "$CAMERA_IP" || -z "$CAMERA_PASS" ]]; then
    echo "Usage: $0 <camera-ip> [username] <password>"
    echo "Example: $0 192.168.1.100 admin mypassword"
    exit 1
fi

echo "Testing camera at $CAMERA_IP..."

# Test 1: Ping
echo -n "Network reachability... "
ping -c 1 -W 2 "$CAMERA_IP" &>/dev/null && echo "OK" || { echo "FAIL"; exit 1; }

# Test 2: RTSP port
echo -n "RTSP port (554)... "
nc -zw2 "$CAMERA_IP" 554 && echo "OK" || { echo "FAIL"; exit 1; }

# Test 3: Main stream
echo -n "Main stream... "
MAIN_URL="rtsp://${CAMERA_USER}:${CAMERA_PASS}@${CAMERA_IP}:554/h264Preview_01_main"
ffprobe -v quiet -show_entries stream=codec_type -of default=noprint_wrappers=1 "$MAIN_URL" 2>/dev/null && echo "OK" || { echo "FAIL"; exit 1; }

# Test 4: Sub stream
echo -n "Sub stream... "
SUB_URL="rtsp://${CAMERA_USER}:${CAMERA_PASS}@${CAMERA_IP}:554/h264Preview_01_sub"
ffprobe -v quiet -show_entries stream=codec_type -of default=noprint_wrappers=1 "$SUB_URL" 2>/dev/null && echo "OK" || { echo "FAIL"; exit 1; }

# Test 5: Capture test frame
echo -n "Capture test frame... "
ffmpeg -y -rtsp_transport tcp -i "$MAIN_URL" -frames:v 1 -q:v 2 /tmp/camera-test.jpg 2>/dev/null && echo "OK" || { echo "FAIL"; exit 1; }

echo ""
echo "Camera tests passed!"
echo "Test frame saved to /tmp/camera-test.jpg"
echo ""
echo "Add this to Frigate config:"
echo ""
echo "go2rtc:"
echo "  streams:"
echo "    camera_name:"
echo "      - rtsp://${CAMERA_USER}:\${FRIGATE_RTSP_PASSWORD}@${CAMERA_IP}:554/h264Preview_01_main"
```

---

## 7. Home Assistant Integration

### 7.1 MQTT Configuration

Add to Home Assistant `configuration.yaml`:

```yaml
mqtt:
  broker: <GPU_SERVER_IP>
  port: 1883
  discovery: true
  discovery_prefix: homeassistant
```

### 7.2 Frigate Integration

1. Install Frigate integration via HACS
2. Configuration:
   - URL: `http://<GPU_SERVER_IP>:5000`
   - MQTT: Use existing broker

### 7.3 Automation Examples

```yaml
# Example: Doorbell person detection
automation:
  - alias: "Doorbell Person Detected"
    trigger:
      - platform: mqtt
        topic: frigate/events
        value_template: "{{ value_json.type }}"
        payload: "new"
    condition:
      - condition: template
        value_template: "{{ trigger.payload_json.after.camera == 'front_door' }}"
      - condition: template
        value_template: "{{ 'person' in trigger.payload_json.after.current_zones }}"
    action:
      - service: notify.mobile_app
        data:
          title: "Doorbell"
          message: "Person at front door"
          data:
            image: "/api/frigate/notifications/{{ trigger.payload_json.after.id }}/thumbnail.jpg"
            
  - alias: "Unknown Person Alert"
    trigger:
      - platform: mqtt
        topic: double-take/matches
    condition:
      - condition: template
        value_template: "{{ trigger.payload_json.match == false }}"
    action:
      - service: notify.mobile_app
        data:
          title: "Unknown Person"
          message: "Unknown person detected at {{ trigger.payload_json.camera }}"
```

---

## 8. Operational Runbook

### 8.1 Daily Operations

**Automatic via cron:**
```cron
# /etc/cron.d/security-stack
*/5 * * * * root /opt/security-stack/scripts/health-check.sh
0 3 * * * root /opt/security-stack/scripts/backup.sh
```

### 8.2 Common Tasks

| Task | Command |
|------|---------|
| View all logs | `make logs` |
| View Frigate logs | `make logs-frigate` |
| Restart everything | `make restart` |
| Check status | `make status` |
| Update images | `make update` |

### 8.3 Troubleshooting

**Frigate won't start:**
```bash
docker logs frigate 2>&1 | tail -50
# Common issues:
# - TensorRT model compilation failed → delete /config/model_cache and restart
# - RTSP connection failed → check camera IP and credentials
# - GPU not available → check nvidia-smi and container runtime
```

**Camera not connecting:**
```bash
./scripts/test-camera.sh <ip> admin <password>
# Verify RTSP URLs match camera documentation
```

**Face recognition not working:**
```bash
docker logs double-take 2>&1 | tail -50
# Check CompreFace API key in double-take config
```

**NFS mount issues:**
```bash
sudo mount -v /mnt/synology/frigate
# Check Synology NFS permissions
# Check firewall rules
```

### 8.4 Adding a New Camera

1. Test camera connectivity:
   ```bash
   ./scripts/test-camera.sh <ip> admin <password>
   ```

2. Add to Frigate config (`frigate/config/config.yml`):
   ```yaml
   go2rtc:
     streams:
       new_camera:
         - rtsp://admin:${FRIGATE_RTSP_PASSWORD}@<ip>:554/h264Preview_01_main
   
   cameras:
     new_camera:
       enabled: true
       ffmpeg:
         inputs:
           - path: rtsp://admin:${FRIGATE_RTSP_PASSWORD}@<ip>:554/h264Preview_01_sub
             roles: [detect]
           - path: rtsp://admin:${FRIGATE_RTSP_PASSWORD}@<ip>:554/h264Preview_01_main
             roles: [record]
       detect:
         enabled: true
         width: 1280
         height: 720
         fps: 5
   ```

3. Restart Frigate:
   ```bash
   make restart-frigate
   ```

4. Configure zones in Frigate UI

5. Add to Double-Take config if face recognition needed

---

## 9. Security Considerations

### 9.1 Network Security

- All services bound to Docker bridge network (not exposed to internet)
- External access via Tailscale only
- MQTT without auth initially for simplicity → add password file for production

### 9.2 Secret Management

- All secrets in `.env` file (gitignored)
- Camera passwords rotated annually
- CompreFace API key regeneratable via UI

### 9.3 Data Retention

- Recordings: 14 days motion, 60 days events
- Snapshots: 60 days
- Face data: Indefinite (manual cleanup)
- Plates: Indefinite (manual cleanup)

---

## 10. Future Enhancements (Phase 2+)

### 10.1 Additional Cameras
- Garage wide (Reolink Duo 3 WiFi)
- Garage zoom (Reolink RLC-811WA)
- Backyard (Reolink Argus 4 Pro)

### 10.2 License Plate Pipeline
- CodeProject.AI or Plate Recognizer integration
- Plate database with known/unknown classification
- Alerting on unknown vehicles

### 10.3 Audio Intelligence
- Whisper integration for doorbell audio
- Keyword detection (help, fire, etc.)
- Conversation logging

### 10.4 Advanced Automations
- Presence-aware arming/disarming
- Face-based unlock suggestions
- Package delivery tracking

---

## Appendix A: Environment Variables Reference

```bash
# /opt/security-stack/.env.example

# ===========================================
# REQUIRED - Must be set before first run
# ===========================================

# Camera RTSP password (same for all Reolink cameras)
FRIGATE_RTSP_PASSWORD=your_camera_password

# Doorbell camera IP address
DOORBELL_IP=192.168.x.x

# GPU server IP (this machine)
HOST_IP=192.168.x.x

# Synology NAS IP
SYNOLOGY_IP=192.168.x.x

# ===========================================
# OPTIONAL - Defaults provided
# ===========================================

# NFS mount path for Frigate storage
NFS_FRIGATE_PATH=/mnt/synology/frigate

# CompreFace database password
COMPREFACE_DB_PASSWORD=compreface

# CompreFace API key (get from UI after first run)
COMPREFACE_API_KEY=

# Plate Recognizer license key (optional)
PLATE_RECOGNIZER_KEY=
```

---

## Appendix B: Port Reference

| Port | Service | Protocol | Description |
|------|---------|----------|-------------|
| 1883 | Mosquitto | MQTT | Message broker |
| 9001 | Mosquitto | WebSocket | MQTT over WS |
| 5000 | Frigate | HTTP | Web UI and API |
| 8554 | Frigate | RTSP | Restreaming |
| 8555 | Frigate | WebRTC | Live view |
| 8000 | CompreFace | HTTP | Face recognition UI |
| 3000 | Double-Take | HTTP | Face matching UI |
| 8001 | Plate Recognizer | HTTP | ALPR API |
| 9000 | Whisper | HTTP | Speech-to-text API |

---

*End of Specification*
