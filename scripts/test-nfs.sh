#!/bin/bash
# Test NFS setup with Synology
# Run this after updating SYNOLOGY_IP in .env

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [[ ! -f .env ]]; then
    echo -e "${RED}Error: .env file not found${NC}"
    exit 1
fi

source .env

echo "=========================================="
echo "NFS Configuration Test"
echo "=========================================="
echo ""
echo "Synology IP: $SYNOLOGY_IP"
echo "Mount point: ${NFS_FRIGATE_PATH:-/mnt/synology/frigate}"
echo ""

MOUNT_POINT="${NFS_FRIGATE_PATH:-/mnt/synology/frigate}"
NFS_EXPORT="${SYNOLOGY_IP}:/volume1/frigate"

# Test 1: Can we reach Synology?
echo -n "1. Network connectivity... "
if ping -c 1 -W 2 "$SYNOLOGY_IP" &>/dev/null; then
    echo -e "${GREEN}[PASS]${NC} Synology reachable"
else
    echo -e "${RED}[FAIL]${NC} Cannot ping Synology"
    echo "   Check network and SYNOLOGY_IP in .env"
    exit 1
fi

# Test 2: Is NFS port open?
echo -n "2. NFS service... "
if nc -zw2 "$SYNOLOGY_IP" 2049 &>/dev/null; then
    echo -e "${GREEN}[PASS]${NC} NFS port 2049 open"
else
    echo -e "${RED}[FAIL]${NC} NFS port 2049 not accessible"
    echo "   Enable NFS service on Synology:"
    echo "   Control Panel → File Services → NFS → Enable NFS"
    exit 1
fi

# Test 3: Can we showmount?
echo -n "3. NFS exports... "
if showmount -e "$SYNOLOGY_IP" 2>/dev/null | grep -q "/volume1/frigate"; then
    echo -e "${GREEN}[PASS]${NC} /volume1/frigate is exported"
else
    echo -e "${YELLOW}[WARN]${NC} /volume1/frigate not found in exports"
    echo ""
    echo "   Current exports from $SYNOLOGY_IP:"
    showmount -e "$SYNOLOGY_IP" 2>/dev/null || echo "   (none or permission denied)"
    echo ""
    echo "   On Synology, create NFS share:"
    echo "   Control Panel → Shared Folder → Create 'frigate'"
    echo "   Then: Control Panel → Shared Folder → Edit 'frigate' → NFS Permissions"
    echo "   Add: ${HOST_IP} with read/write access"
    exit 1
fi

# Test 4: Create mount point
echo -n "4. Mount point... "
if [[ ! -d "$MOUNT_POINT" ]]; then
    echo -n "creating... "
    sudo mkdir -p "$MOUNT_POINT"
fi
echo -e "${GREEN}[PASS]${NC} $MOUNT_POINT exists"

# Test 5: Already mounted?
echo -n "5. Mount status... "
if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    echo -e "${GREEN}[INFO]${NC} Already mounted"
else
    echo -e "${YELLOW}[INFO]${NC} Not mounted, attempting..."

    # Try to mount
    if sudo mount -t nfs "${NFS_EXPORT}" "$MOUNT_POINT" 2>/dev/null; then
        echo -e "${GREEN}[PASS]${NC} Successfully mounted"
    else
        echo -e "${RED}[FAIL]${NC} Mount failed"
        echo ""
        echo "   Check Synology NFS permissions:"
        echo "   - This server's IP (${HOST_IP}) must be in allowed hosts"
        echo "   - Permissions should be: read/write, no_root_squash"
        exit 1
    fi
fi

# Test 6: Write test
echo -n "6. Write permission... "
TEST_FILE="$MOUNT_POINT/.write-test-$$"
if touch "$TEST_FILE" 2>/dev/null; then
    rm "$TEST_FILE"
    echo -e "${GREEN}[PASS]${NC} Can write to NFS share"
else
    echo -e "${RED}[FAIL]${NC} Cannot write to NFS share"
    echo "   Check Synology permissions - needs read/write access"
    exit 1
fi

# Test 7: Add to fstab?
echo -n "7. fstab entry... "
if grep -q "$NFS_EXPORT" /etc/fstab 2>/dev/null; then
    echo -e "${GREEN}[INFO]${NC} Already in fstab"
else
    echo -e "${YELLOW}[INFO]${NC} Not in fstab"
    echo ""
    echo "   To auto-mount on boot, run:"
    echo "   echo '$NFS_EXPORT $MOUNT_POINT nfs rw,hard,intr,noatime 0 0' | sudo tee -a /etc/fstab"
fi

echo ""
echo -e "${GREEN}=========================================="
echo "✓ NFS Ready"
echo "==========================================${NC}"
echo ""
echo "Mount point: $MOUNT_POINT"
echo "Available space:"
df -h "$MOUNT_POINT" | tail -1
echo ""
echo "You're ready to proceed with: make setup"
