# Home Security AI System

Local-first, AI-powered home security camera system built on commodity hardware with GPU acceleration. Prioritizes privacy, reliability during network outages, and low maintenance overhead.

## Quick Start

```bash
# 1. Copy environment template
cp .env.example .env

# 2. Edit .env with your values
nano .env

# 3. Run setup script
make setup

# 4. Check status
make status
```

## System Overview

### Hardware

- **GPU Server**: AMD Epyc 128-thread, 512GB RAM, 3× NVIDIA 3090 24GB (Kubuntu)
- **Storage**: Synology DS1522+ with ~12TB for recordings
- **Network**: UniFi Dream Machine Pro + Asus ZenWiFi mesh
- **Cameras**: Reolink doorbell + additional cameras (expandable)

### Software Stack

```
┌─────────────────────────────────────────────────┐
│            GPU Server (Docker Stack)            │
│                                                 │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐  │
│  │ Frigate  │  │ Double-  │  │  Compreface  │  │
│  │ (GPU 0)  │  │   Take   │  │ (Face recog) │  │
│  └────┬─────┘  └────┬─────┘  └──────┬───────┘  │
│       │             │                │          │
│       └─────────────┴────────────────┘          │
│                     │                           │
│              ┌──────┴──────┐                    │
│              │    MQTT     │                    │
│              │  Mosquitto  │                    │
│              └─────────────┘                    │
└─────────────────────────────────────────────────┘
                     │
          ┌──────────┴──────────┐
          │  Synology DS1522+   │
          │  - Home Assistant   │
          │  - NFS Storage      │
          └─────────────────────┘
```

## Installation

### Prerequisites

- Docker with Docker Compose v2
- NVIDIA Container Toolkit
- NFS client (`nfs-common`)
- Synology NAS with NFS export configured

### Initial Setup

1. **Clone and configure**:
   ```bash
   cd /opt
   git clone <repo> security-stack
   cd security-stack
   cp .env.example .env
   nano .env  # Configure your values
   ```

2. **Run pre-deployment tests**:
   ```bash
   make test-pre
   ```

3. **Deploy the stack**:
   ```bash
   make setup
   ```

4. **Verify deployment**:
   ```bash
   make test-post
   make status
   ```

### Post-Installation Configuration

1. **CompreFace Setup**:
   - Access: http://\<HOST_IP\>:8000
   - Create account (local only, no email needed)
   - Create "Recognition" service
   - Copy API key to `.env` as `COMPREFACE_API_KEY`
   - Restart Double-Take: `make restart-double-take`

2. **Frigate Familiarization**:
   - Access: http://\<HOST_IP\>:5000
   - Explore the UI (no cameras yet)
   - Review detection zones interface

3. **Home Assistant Integration** (optional):
   - Add MQTT broker: mqtt://\<GPU_SERVER_IP\>:1883
   - Install Frigate integration via HACS
   - Configure Frigate URL: http://\<GPU_SERVER_IP\>:5000

## Adding Your First Camera

When your doorbell arrives:

1. **Test camera connectivity**:
   ```bash
   make test-camera IP=192.168.1.100 PASS=your_camera_password
   ```

2. **Update configuration**:
   ```bash
   # Update .env
   echo "DOORBELL_IP=192.168.1.100" >> .env

   # Edit frigate config
   nano frigate/config/config.yml
   # Uncomment the front_door camera section
   ```

3. **Restart Frigate**:
   ```bash
   make restart-frigate
   ```

4. **Verify in UI**:
   - http://\<HOST_IP\>:5000
   - Should see live stream within 30 seconds

## Daily Operations

### Common Commands

```bash
# View all logs
make logs

# View specific service logs
make logs-frigate
make logs-mqtt

# Restart services
make restart              # All services
make restart-frigate      # Specific service

# Check system health
make health

# Monitor GPU usage
make gpu

# Update images
make update
```

### Endpoints

| Service | URL | Purpose |
|---------|-----|---------|
| Frigate | http://\<HOST_IP\>:5000 | NVR and live view |
| CompreFace | http://\<HOST_IP\>:8000 | Face recognition management |
| Double-Take | http://\<HOST_IP\>:3000 | Face detection events |
| MQTT | mqtt://\<HOST_IP\>:1883 | Message broker |

### Monitoring

Health checks run automatically every 5 minutes via cron. To set up:

```bash
# Create cron file
sudo tee /etc/cron.d/security-stack << EOF
*/5 * * * * root /opt/security-stack/scripts/health-check.sh
0 3 * * * root /opt/security-stack/scripts/backup.sh
EOF

# Restart cron
sudo systemctl restart cron
```

Health status publishes to MQTT topic: `security-stack/health`

## Troubleshooting

### Frigate Won't Start

```bash
# Check logs
docker logs frigate

# Common issues:
# 1. TensorRT model compilation failed
#    Fix: Delete model cache and restart
docker exec frigate rm -rf /config/model_cache
make restart-frigate

# 2. RTSP connection failed
#    Fix: Verify camera IP and credentials in .env

# 3. GPU not available
#    Fix: Check NVIDIA container toolkit
nvidia-smi
docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi
```

### Camera Not Connecting

```bash
# Test camera
./scripts/test-camera.sh <camera-ip> admin <password>

# Check network
ping <camera-ip>

# Verify RTSP port
nc -zv <camera-ip> 554

# Check credentials
# Try accessing camera web UI: http://<camera-ip>
```

### Face Recognition Not Working

```bash
# Check Double-Take logs
docker logs double-take

# Verify CompreFace API key
docker exec double-take cat /.storage/config/config.yml | grep key

# Test CompreFace directly
curl http://localhost:8000
```

### NFS Mount Issues

```bash
# Check mount status
mountpoint /mnt/synology/frigate

# Manually mount
sudo mount /mnt/synology/frigate

# Verify permissions
touch /mnt/synology/frigate/.test && rm /mnt/synology/frigate/.test

# On Synology:
# - NFS service must be enabled
# - /volume1/frigate must be exported
# - GPU server IP must be in allowed list
```

### High GPU Memory Usage

```bash
# Check GPU status
nvidia-smi

# Typical usage:
# - Frigate: 2-4GB (depends on camera count)
# - Idle: < 1GB

# If > 20GB on GPU 0:
# - Check for stuck processes
# - Restart Frigate: make restart-frigate
```

## Adding More Cameras

1. **Test new camera**:
   ```bash
   ./scripts/test-camera.sh <camera-ip> admin <password>
   ```

2. **Add to Frigate config** (`frigate/config/config.yml`):
   ```yaml
   go2rtc:
     streams:
       camera_name:
         - "rtsp://admin:${FRIGATE_RTSP_PASSWORD}@<ip>:554/h264Preview_01_main"

   cameras:
     camera_name:
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

3. **Restart Frigate**:
   ```bash
   make restart-frigate
   ```

4. **Configure zones in Frigate UI**

## Architecture Decisions

### Why These Technologies?

- **Frigate**: Best-in-class NVR with GPU acceleration, active development
- **TensorRT**: 3-5× faster than standard models on NVIDIA GPUs
- **CompreFace**: Open source, local-only, no cloud dependencies
- **Mosquitto**: Lightweight, standard MQTT broker
- **Docker Compose**: Simple orchestration, easy to manage

### Storage Strategy

- **NFS to Synology**: Centralized, RAID-protected, expandable
- **Retention**: 14 days motion, 60 days events (configurable)
- **Local cache**: 1GB tmpfs for Frigate processing

### GPU Allocation

- **GPU 0**: Frigate + TensorRT (primary workload)
- **GPU 1**: Whisper STT (future, profiles only)
- **GPU 2**: Plate Recognizer (future, profiles only)

## Security Considerations

- All services bound to Docker bridge (not exposed to internet)
- External access only via Tailscale VPN
- MQTT: Anonymous initially (set password for production)
- Camera credentials stored in `.env` (gitignored)
- No cloud services required

## Backup & Recovery

### Configuration Backup

```bash
# Manual backup
tar -czf backup-$(date +%Y%m%d).tar.gz \
  .env \
  docker-compose.yml \
  frigate/config/ \
  mosquitto/config/ \
  double-take/config.yml

# Automated (via cron)
./scripts/backup.sh
```

### Recovery

```bash
# Extract backup
tar -xzf backup-YYYYMMDD.tar.gz

# Restart services
make restart
```

## Future Enhancements

- [ ] License plate recognition (CodeProject.AI)
- [ ] Audio intelligence with Whisper
- [ ] Additional cameras (garage, backyard)
- [ ] Advanced automations in Home Assistant
- [ ] Package delivery detection
- [ ] Presence-aware arming/disarming

## Directory Structure

```
/opt/security-stack/
├── docker-compose.yml          # Main orchestration
├── .env                        # Secrets (gitignored)
├── .env.example                # Template
├── README.md                   # This file
├── Makefile                    # Common operations
├── pyproject.toml              # Python project config
├── scripts/
│   ├── setup.sh               # Initial setup
│   ├── health-check.sh        # Monitoring
│   ├── test-camera.sh         # Camera testing
│   ├── test-pre-deploy.sh     # Pre-deployment tests
│   └── test-post-deploy.sh    # Post-deployment tests
├── frigate/
│   └── config/
│       └── config.yml         # Frigate configuration
├── mosquitto/
│   ├── config/
│   │   └── mosquitto.conf
│   ├── data/                  # Persistent data
│   └── log/                   # Logs
├── double-take/
│   └── config.yml
└── compreface/
    └── postgres/              # Database
```

## Support

- Check logs: `make logs` or `make logs-<service>`
- Run health check: `make health`
- See detailed spec: `SPEC.md`

## License

Private use only. Not for redistribution.

---

**Version**: 1.0.0
**Last Updated**: 2026-01-19
**Maintainer**: Matt
