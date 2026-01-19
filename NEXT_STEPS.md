# Next Steps - GPU Server Deployment

## Status
✅ All code validated and committed
✅ .env file created with detected IP (192.168.1.123)
⚠️  Docker group needs terminal restart
⚠️  Need Synology IP and NFS configuration

## Immediate Actions (5 minutes)

### 1. Restart Your Terminal
The docker group membership needs a fresh session:
```bash
# Close this terminal and open a new one, OR
# Log out and log back in
```

Verify it worked:
```bash
docker ps
# Should work without sudo
```

### 2. Update .env File
Edit the configuration file:
```bash
cd /mnt/storage/projects/home_security
nano .env
```

Update these values:
- `SYNOLOGY_IP=192.168.1.XXX` (your Synology NAS IP)
- `FRIGATE_RTSP_PASSWORD=your_camera_password` (set camera password)
- `DOORBELL_IP` (leave as is, will update when camera arrives)

### 3. Configure Synology NFS (if not already done)
On your Synology:
1. Control Panel → File Services → NFS
   - ☑ Enable NFS service

2. Control Panel → Shared Folder
   - Create folder: `frigate`

3. Edit `frigate` folder → NFS Permissions
   - Click "Create"
   - Hostname/IP: `192.168.1.123` (this GPU server)
   - Privilege: Read/Write
   - Squash: No mapping
   - Security: sys
   - Enable async: ☑
   - Click OK

## Testing Sequence

### Test 1: GPU Server Capabilities
```bash
cd /mnt/storage/projects/home_security
./scripts/test-gpu-server.sh
```

**What it does:**
- ✓ Verifies Docker access
- ✓ Tests all 3 GPUs accessible through Docker
- ✓ Validates docker-compose.yml
- ✓ Pulls all Docker images (~5GB, takes 10-15 min)

**Expected result:** All tests pass, images cached

### Test 2: NFS Storage
```bash
./scripts/test-nfs.sh
```

**What it does:**
- ✓ Tests network connectivity to Synology
- ✓ Verifies NFS service running
- ✓ Checks NFS export exists
- ✓ Mounts the share
- ✓ Tests write permissions

**Expected result:** NFS mounted and writable

### Test 3: Pre-Deployment Validation
```bash
make test-pre
```

**What it does:**
- ✓ Comprehensive check of all prerequisites
- ✓ Validates configurations
- ✓ Checks environment variables

**Expected result:** All pre-deployment tests pass

## Deployment (When Tests Pass)

### Option A: Full Setup (Recommended First Time)
```bash
make setup
```

**What it does:**
- Runs all prerequisite checks
- Configures NFS mount in /etc/fstab
- Creates directory structure
- Starts all services in correct order
- Waits for services to be healthy
- Runs post-deployment validation

**Duration:** ~10-15 minutes (TensorRT model compilation on first run)

**Expected output:**
- All services started
- Frigate UI accessible: http://192.168.1.123:5000
- CompreFace UI accessible: http://192.168.1.123:8000
- Double-Take UI accessible: http://192.168.1.123:3000

### Option B: Quick Start (If You've Run Setup Before)
```bash
make start
```

## Post-Deployment Configuration

### 1. CompreFace Setup (5 minutes)
```bash
# Access UI
firefox http://192.168.1.123:8000
```

Steps:
1. Create local account (username/password)
2. Click "Create Application" → name it "Home Security"
3. Click "Recognition" → "Add Service"
4. Copy the API key shown
5. Add to .env:
   ```bash
   nano .env
   # Update: COMPREFACE_API_KEY=<paste key here>
   ```
6. Restart Double-Take:
   ```bash
   make restart-double-take
   ```

### 2. Verify Services (2 minutes)
```bash
make status
make test-post
```

All services should be running and healthy.

### 3. Set Up Monitoring (Optional, 2 minutes)
```bash
sudo cp scripts/security-stack.cron /etc/cron.d/security-stack
sudo systemctl restart cron
```

This enables:
- Health checks every 5 minutes
- Auto-restart of failed services
- Daily backups at 3 AM

## When Camera Arrives Tomorrow

### Quick Integration (5 minutes)
```bash
# 1. Test camera
make test-camera IP=<camera-ip> PASS=<camera-password>

# 2. Update configuration
nano .env
# Set: DOORBELL_IP=<camera-ip>

nano frigate/config/config.yml
# Uncomment the entire "cameras:" section (line ~253 to end)

# 3. Restart Frigate
make restart-frigate

# 4. Verify
firefox http://192.168.1.123:5000
# Should see live stream within 30 seconds
```

## Troubleshooting

### Docker not working?
```bash
# Check groups
groups
# Should include "docker"

# If not, log out and back in
# Or run: newgrp docker
```

### NFS issues?
```bash
# Check Synology from GPU server
ping <synology-ip>
showmount -e <synology-ip>

# Manual mount test
sudo mount -t nfs <synology-ip>:/volume1/frigate /mnt/synology/frigate
```

### Services not starting?
```bash
make logs
# Check for specific errors

# Restart everything
make restart
```

## Quick Reference

### Common Commands
```bash
make help           # Show all commands
make status         # Service status
make logs           # All logs
make logs-frigate   # Frigate logs only
make health         # Health check
make gpu            # Monitor GPU usage
```

### Key Files
- `.env` - Configuration (edit this)
- `frigate/config/config.yml` - Camera config
- `docker-compose.yml` - Service definitions
- `README.md` - Full documentation

### UIs
- **Frigate**: http://192.168.1.123:5000 (NVR & live view)
- **CompreFace**: http://192.168.1.123:8000 (face recognition)
- **Double-Take**: http://192.168.1.123:3000 (face events)

## Current Status

- ✅ Code complete and validated
- ✅ GPU server detected (3x RTX 3090)
- ✅ Server IP: 192.168.1.123
- ✅ .env file created
- ⏳ Waiting for: Terminal restart + Synology config + camera arrival

**You're 95% ready!** Just need to restart terminal, configure Synology NFS, and run the tests.
