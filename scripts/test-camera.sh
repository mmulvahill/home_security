#!/bin/bash
# Test camera RTSP connectivity before adding to Frigate.
# Usage: ./test-camera.sh <camera-ip> [username] <password>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

CAMERA_IP="${1:-}"
CAMERA_USER="${2:-admin}"
CAMERA_PASS="${3:-}"

# If only 2 args, assume second is password
if [[ $# -eq 2 ]]; then
    CAMERA_PASS="$2"
    CAMERA_USER="admin"
fi

if [[ -z "$CAMERA_IP" || -z "$CAMERA_PASS" ]]; then
    echo "Usage: $0 <camera-ip> [username] <password>"
    echo ""
    echo "Examples:"
    echo "  $0 192.168.1.100 mypassword"
    echo "  $0 192.168.1.100 admin mypassword"
    exit 1
fi

echo "======================================"
echo "Camera Connectivity Test"
echo "======================================"
echo "IP: $CAMERA_IP"
echo "Username: $CAMERA_USER"
echo ""

MAIN_URL="rtsp://${CAMERA_USER}:${CAMERA_PASS}@${CAMERA_IP}:554/h264Preview_01_main"
SUB_URL="rtsp://${CAMERA_USER}:${CAMERA_PASS}@${CAMERA_IP}:554/Preview_01_sub"

# Ping
echo -n "Network reachability... "
if ping -c 1 -W 2 "$CAMERA_IP" &>/dev/null; then
    test_pass "reachable"
else
    test_fail "cannot ping camera"
    exit 1
fi

# RTSP port
echo -n "RTSP port (554)... "
if nc -zw2 "$CAMERA_IP" 554 2>/dev/null; then
    test_pass "open"
else
    test_fail "not accessible"
    exit 1
fi

# HTTP port
echo -n "HTTP port (80)... "
if nc -zw2 "$CAMERA_IP" 80 2>/dev/null; then
    test_pass "open (web UI available)"
else
    log_info "not accessible (not critical)"
fi

# Main stream
echo -n "Main stream... "
if timeout 10 ffprobe -v quiet -show_entries stream=codec_type -of default=noprint_wrappers=1 "$MAIN_URL" 2>/dev/null | grep -q video; then
    test_pass "accessible"
else
    test_fail "cannot access main stream (check credentials / RTSP path)"
    exit 1
fi

# Sub stream
echo -n "Sub stream... "
if timeout 10 ffprobe -v quiet -show_entries stream=codec_type -of default=noprint_wrappers=1 "$SUB_URL" 2>/dev/null | grep -q video; then
    test_pass "accessible"
else
    test_fail "cannot access sub stream"
fi

# Capture test frame
echo -n "Capture test frame... "
TEST_FRAME="/tmp/camera-test-${CAMERA_IP}.jpg"
if timeout 15 ffmpeg -y -rtsp_transport tcp -i "$MAIN_URL" -frames:v 1 -q:v 2 "$TEST_FRAME" &>/dev/null; then
    test_pass "saved to $TEST_FRAME"
else
    test_fail "could not capture frame"
fi

# Stream info
echo ""
echo "Stream information:"
ffprobe -v error -select_streams v:0 \
    -show_entries stream=codec_name,width,height,r_frame_rate,bit_rate \
    -of default=noprint_wrappers=1 "$MAIN_URL" 2>/dev/null | while IFS='=' read -r key value; do
    echo "   $key: $value"
done

test_summary "Camera Test Results"
