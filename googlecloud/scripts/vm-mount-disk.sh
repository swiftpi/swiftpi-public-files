#!/bin/bash

# Mount one Google Cloud persistent disk to a specified path.
#
# Usage:
#   bash vm-mount-disk-script.sh <disk-name> <mount-path>
#
# Example:
#   bash vm-mount-disk-script.sh disk-data /opt/apps
#
# Before running this script, make sure the disk is already attached to the VM.

set -euo pipefail

# Require exactly two arguments
if [ "$#" -ne 2 ]; then
    echo "Error: Expected exactly 2 arguments."
    echo "Usage: bash vm-mount-disk-script.sh <disk-name> <mount-path>"
    echo "Example: bash vm-mount-disk-script.sh disk-apps /opt/apps"
    exit 1
fi

DISKNAME="$1"
FOLDER="$2"
DISK="/dev/disk/by-id/google-$DISKNAME"

echo "=== Current Attached Disks ==="
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS,MODEL
echo "=============================="
echo "Disk:       $DISKNAME"
echo "Device:     $DISK"
echo "Mount path: $FOLDER"
echo "=============================="

# Verify the Google Cloud disk symlink exists
if [ ! -L "$DISK" ]; then
    echo "Error: $DISK does not exist."
    echo "Make sure disk '$DISKNAME' is attached to this VM."
    exit 1
fi

# Resolve actual device path
REAL_DEV=$(readlink -f "$DISK")

echo "Disk $DISKNAME points to device: $REAL_DEV"
lsblk -f "$REAL_DEV"

# Check whether the disk already has a filesystem
if sudo blkid -s TYPE -o value "$DISK" >/dev/null 2>&1; then
    FSTYPE=$(sudo blkid -s TYPE -o value "$DISK")
    UUID=$(sudo blkid -s UUID -o value "$DISK")

    echo "Disk already has filesystem: $FSTYPE"
    echo "UUID: $UUID"
    echo "Existing filesystem will NOT be formatted."

    sudo mkdir -p "$FOLDER"

    # Add fstab entry if this UUID is not already configured
    if ! grep -q "UUID=$UUID" /etc/fstab; then
        sudo cp /etc/fstab "/etc/fstab.backup.before.$DISKNAME"

        echo "UUID=$UUID $FOLDER $FSTYPE defaults,nofail 0 2" \
            | sudo tee -a /etc/fstab
    fi

    sudo systemctl daemon-reload

    # Mount if not already mounted at the target path
    if ! findmnt "$FOLDER" >/dev/null 2>&1; then
        sudo mount "$FOLDER"
    fi

else
    echo "No filesystem detected."
    echo "Formatting $DISK with ext4..."

    sudo mkfs.ext4 \
        -m 0 \
        -E lazy_itable_init=0,lazy_journal_init=0,discard \
        "$DISK"

    sudo mkdir -p "$FOLDER"

    # Mount temporarily
    sudo mount "$DISK" "$FOLDER"

    echo "Temporary mount check:"
    findmnt "$FOLDER"

    UUID=$(sudo blkid -s UUID -o value "$DISK")

    echo "Generated UUID: $UUID"

    # Back up fstab
    sudo cp /etc/fstab "/etc/fstab.backup.before.$DISKNAME"

    # Add persistent mount configuration
    if ! grep -q "UUID=$UUID" /etc/fstab; then
        echo "UUID=$UUID $FOLDER ext4 defaults,nofail 0 2" \
            | sudo tee -a /etc/fstab
    fi

    # Verify fstab configuration
    echo "Testing fstab persistence..."

    sudo umount "$FOLDER"
    sudo systemctl daemon-reload
    sudo mount -a
fi

echo "=============================================="
echo "Success!"
echo "Disk:  $DISKNAME"
echo "Mount: $FOLDER"
echo "=============================================="

findmnt "$FOLDER"
df -hT "$FOLDER"
