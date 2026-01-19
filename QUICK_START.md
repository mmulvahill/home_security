# Quick Start Guide - Camera Deployment

## When Your Camera Arrives

### Step 1: Test Camera (5 minutes)
```bash
cd /mnt/storage/projects/home_security

# Test camera connectivity
make test-camera IP=<camera-ip> PASS=<camera-password>
```

**Expected output**: All tests pass, test frame captured

### Step 2: Configure Camera in System (2 minutes)
```bash
# 1. Add camera IP to environment
echo "DOORBELL_IP=<camera-ip>" >> .env

# 2. Edit Frigate config
nano frigate/config/config.yml
# Uncomment the entire "cameras:" section at the bottom
# (Lines starting with "# cameras:" through the end)
```

### Step 3: Restart Frigate (1 minute)
```bash
make restart-frigate

# Watch logs to verify camera connection
make logs-frigate
```

**Look for**: "front_door: ffmpeg sent a broken frame"... then "front_door: 10.0 fps"

### Step 4: Verify in UI (2 minutes)
1. Open: `http://<HOST_IP>:5000`
2. Click "Cameras" → "front_door"
3. Should see live stream within 30 seconds
4. Click "Debug" → verify detection is running

### Step 5: Configure Zones (Optional, 5 minutes)
1. In Frigate UI, go to front_door camera
2. Click "Mask & Zone Editor"
3. Draw zones for areas you want to monitor (e.g., "porch", "driveway")
4. Save and restart: `make restart-frigate`

### Step 6: Test Face Recognition (10 minutes)
1. Access Double-Take: `http://<HOST_IP>:3000`
2. Wait for a person detection event
3. Click on detected face
4. Train the face with a name
5. Next detection should recognize the person

## Troubleshooting Quick Fixes

### Camera not connecting?
```bash
# Check camera is reachable
ping <camera-ip>

# Verify RTSP credentials
# Try accessing camera web UI: http://<camera-ip>

# Check Frigate logs
make logs-frigate | grep -i error
```

### No video in Frigate?
```bash
# Verify camera config is uncommented
grep -A 5 "^cameras:" frigate/config/config.yml

# Check RTSP stream directly
ffplay rtsp://admin:<password>@<camera-ip>:554/h264Preview_01_sub
```

### Face recognition not working?
```bash
# Check CompreFace API key is set
grep COMPREFACE_API_KEY .env

# Verify Double-Take is connected
make logs-double-take | grep -i compreface
```

## Common Commands

```bash
# Restart everything
make restart

# View status
make status

# Check health
make health

# View logs
make logs                  # All services
make logs-frigate         # Just Frigate
make logs-double-take     # Just Double-Take
```

## Next Steps After Camera Works

1. **Set up automations in Home Assistant**
   - Person detection notifications
   - Unknown face alerts
   - Package detection

2. **Configure retention**
   - Edit `frigate/config/config.yml`
   - Adjust `record.retain.days` as needed

3. **Add more cameras**
   - Use `test-camera.sh` for each new camera
   - Add to Frigate config
   - Restart: `make restart-frigate`

4. **Enable automatic updates**
   - `make update` pulls latest images
   - Can add to weekly cron if desired

## Emergency: System Not Working?

```bash
# Nuclear option: restart everything
make stop
make start

# Check what's running
docker ps

# Check system health
make health

# View detailed logs
docker compose logs --tail=100 --follow
```

Need help? Check `VALIDATION_REPORT.md` and `README.md` for detailed troubleshooting.
