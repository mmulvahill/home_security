#!/bin/bash
# Test camera RTSP connectivity before adding to Frigate
# Usage: ./test-camera.sh <camera-ip> [username] <password>

set -euo pipefail

CAMERA_IP="${1:-}"
CAMERA_USER="${2:-admin}"
CAMERA_PASS="${3:-}"

# If only 2 args provided, assume second is password
if [[ $# -eq 2 ]]; then
    CAMERA_PASS="$2"
    CAMERA_USER="admin"
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
log_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

if [[ -z "$CAMERA_IP" || -z "$CAMERA_PASS" ]]; then
    echo "Usage: $0 <camera-ip> [username] <password>"
    echo ""
    echo "Examples:"
    echo "  $0 192.168.1.100 mypassword           # Uses default username 'admin'"
    echo "  $0 192.168.1.100 admin mypassword     # Specifies username"
    echo ""
    exit 1
fi

echo "======================================"
echo "Camera Connectivity Test"
echo "======================================"
echo "IP: $CAMERA_IP"
echo "Username: $CAMERA_USER"
echo ""

# Test 1: Ping
echo -n "1. Network reachability... "
if ping -c 1 -W 2 "$CAMERA_IP" &>/dev/null; then
    log_pass "Camera is reachable"
else
    log_fail "Cannot ping camera"
    exit 1
fi

# Test 2: RTSP port
echo -n "2. RTSP port (554)... "
if nc -zw2 "$CAMERA_IP" 554 2>/dev/null; then
    log_pass "Port 554 is open"
else
    log_fail "Port 554 not accessible"
    exit 1
fi

# Test 3: HTTP port (for Reolink cameras)
echo -n "3. HTTP port (80)... "
if nc -zw2 "$CAMERA_IP" 80 2>/dev/null; then
    log_pass "Port 80 is open (can access web UI)"
else
    log_info "Port 80 not accessible (not critical)"
fi

# Test 4: Main stream
echo -n "4. Main stream... "
MAIN_URL="rtsp://${CAMERA_USER}:${CAMERA_PASS}@${CAMERA_IP}:554/h264Preview_01_main"
if timeout 10 ffprobe -v quiet -show_entries stream=codec_type -of default=noprint_wrappers=1 "$MAIN_URL" 2>/dev/null | grep -q video; then
    log_pass "Main stream accessible"
else
    log_fail "Cannot access main stream"
    log_info "Try checking:"
    log_info "  - Camera credentials"
    log_info "  - RTSP path format (may vary by model)"
    exit 1
fi

# Test 5: Sub stream
echo -n "5. Sub stream... "
SUB_URL="rtsp://${CAMERA_USER}:${CAMERA_PASS}@${CAMERA_IP}:554/h264Preview_01_sub"
if timeout 10 ffprobe -v quiet -show_entries stream=codec_type -of default=noprint_wrappers=1 "$SUB_URL" 2>/dev/null | grep -q video; then
    log_pass "Sub stream accessible"
else
    log_fail "Cannot access sub stream"
fi

# Test 6: Capture test frame
echo -n "6. Capture test frame... "
TEST_FRAME="/tmp/camera-test-${CAMERA_IP}.jpg"
if timeout 15 ffmpeg -y -rtsp_transport tcp -i "$MAIN_URL" -frames:v 1 -q:v 2 "$TEST_FRAME" &>/dev/null; then
    log_pass "Frame captured successfully"
    log_info "Test frame saved to: $TEST_FRAME"
else
    log_fail "Could not capture test frame"
fi

# Test 7: Get stream info
echo ""
echo "7. Stream information:"
ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height,r_frame_rate,bit_rate -of default=noprint_wrappers=1 "$MAIN_URL" 2>/dev/null | while IFS='=' read key value; do
    echo "   $key: $value"
done

echo ""
log_pass "======================================"
log_pass "Camera tests PASSED!"
log_pass "======================================"
echo ""
echo "Ready to add to Frigate. Use this configuration:"
echo ""
echo "----------------------------------------"
echo "In frigate/config/config.yml:"
echo "----------------------------------------"
echo ""
echo "go2rtc:"
echo "  streams:"
echo "    camera_name:"
echo "      - \"rtsp://${CAMERA_USER}:\${FRIGATE_RTSP_PASSWORD}@${CAMERA_IP}:554/h264Preview_01_main\""
echo ""
echo "cameras:"
echo "  camera_name:"
echo "    enabled: true"
echo "    ffmpeg:"
echo "      inputs:"
echo "        - path: rtsp://${CAMERA_USER}:\${FRIGATE_RTSP_PASSWORD}@${CAMERA_IP}:554/h264Preview_01_sub"
echo "          roles:"
echo "            - detect"
echo "        - path: rtsp://${CAMERA_USER}:\${FRIGATE_RTSP_PASSWORD}@${CAMERA_IP}:554/h264Preview_01_main"
echo "          roles:"
echo "            - record"
echo "    detect:"
echo "      enabled: true"
echo "      width: 640"
echo "      height: 480"
echo "      fps: 10"
echo "----------------------------------------"
echo ""
echo "Don't forget to:"
echo "1. Update DOORBELL_IP in .env to: $CAMERA_IP"
echo "2. Uncomment the camera config in frigate/config/config.yml"
echo "3. Restart Frigate: make restart-frigate"
