#!/bin/bash
# Test NFS connectivity and mount with Synology.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
cd "$PROJECT_DIR"

load_env

echo "=========================================="
echo "NFS Configuration Test"
echo "=========================================="
echo ""
echo "Synology:    ${SYNOLOGY_IP}"
echo "NFS export:  ${SYNOLOGY_NFS_EXPORT}"
echo "Mount point: ${NFS_FRIGATE_PATH:-/mnt/synology/frigate}"
echo ""

MOUNT_POINT="${NFS_FRIGATE_PATH:-/mnt/synology/frigate}"
NFS_SOURCE="${SYNOLOGY_IP}:${SYNOLOGY_NFS_EXPORT}"

# Network
echo -n "Network connectivity... "
if ping -c 1 -W 2 "$SYNOLOGY_IP" &>/dev/null; then
    test_pass "Synology reachable"
else
    test_fail "cannot ping Synology"
    exit 1
fi

# NFS port
echo -n "NFS service... "
if nc -zw2 "$SYNOLOGY_IP" 2049 &>/dev/null; then
    test_pass "port 2049 open"
else
    test_fail "port 2049 closed (enable NFS: Control Panel -> File Services -> NFS)"
    exit 1
fi

# NFS exports
echo -n "NFS exports... "
if showmount -e "$SYNOLOGY_IP" 2>/dev/null | grep -qF "$SYNOLOGY_NFS_EXPORT"; then
    test_pass "$SYNOLOGY_NFS_EXPORT exported"
else
    test_fail "$SYNOLOGY_NFS_EXPORT not found in exports"
    echo ""
    echo "   Current exports:"
    showmount -e "$SYNOLOGY_IP" 2>/dev/null | sed 's/^/   /' || echo "   (none)"
    echo ""
    echo "   On Synology: Shared Folder -> Edit -> NFS Permissions"
    echo "   Add: ${HOST_IP} with read/write access"
    exit 1
fi

# Mount point
echo -n "Mount point... "
if [[ -d "$MOUNT_POINT" ]]; then
    test_pass "$MOUNT_POINT exists"
else
    echo -n "creating... "
    sudo mkdir -p "$MOUNT_POINT"
    test_pass "created $MOUNT_POINT"
fi

# Mount status
echo -n "Mount status... "
if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    test_pass "already mounted"
else
    if sudo mount -t nfs "$NFS_SOURCE" "$MOUNT_POINT" 2>/dev/null; then
        test_pass "mounted successfully"
    else
        test_fail "mount failed (check Synology NFS permissions for ${HOST_IP})"
        exit 1
    fi
fi

# Write test (try as current user first, fall back to sudo since Docker runs as root)
echo -n "Write permission... "
test_file="$MOUNT_POINT/.write-test-$$"
if touch "$test_file" 2>/dev/null; then
    rm "$test_file"
    test_pass "writable (user)"
elif sudo touch "$test_file" 2>/dev/null; then
    sudo rm "$test_file"
    test_warn "writable as root only (Frigate will work, but consider setting Squash to 'No mapping' on Synology)"
else
    test_fail "not writable (check Synology NFS permissions)"
    exit 1
fi

# fstab
echo -n "fstab entry... "
if grep -qF "$NFS_SOURCE" /etc/fstab 2>/dev/null; then
    test_pass "present"
else
    test_warn "not in fstab (will not auto-mount on boot)"
    echo "   To add: echo '${NFS_SOURCE} ${MOUNT_POINT} nfs rw,hard,intr,noatime 0 0' | sudo tee -a /etc/fstab"
fi

echo ""
echo "Available space:"
df -h "$MOUNT_POINT" | tail -1
echo ""

test_summary "NFS Test Results"
