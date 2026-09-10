#!/bin/bash

# Remove one mounted disk from this VM using only its mount path.
#
# This script:
#   1. Finds the device mounted at the given path
#   2. Gets its filesystem UUID
#   3. Unmounts it
#   4. Removes its entry from /etc/fstab
#   5. Removes the mount directory if it is empty
#
# It DOES NOT:
#   - Format the disk
#   - Erase disk data
#   - Detach the disk from Google Cloud
#   - Delete the Google Cloud disk
#
# Usage:
#   bash vm-remove-disk-script.sh <mount-path>
#
# Example:
#   bash vm-remove-disk-script.sh /opt/apps

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Error: Expected exactly 1 argument."
    echo "Usage: bash vm-remove-disk-script.sh <mount-path>"
    echo "Example: bash vm-remove-disk-script.sh /opt/apps"
    exit 1
fi

FOLDER="$1"

echo "=============================================="
echo "Removing mount configuration"
echo "Mount path: $FOLDER"
echo "=============================================="

# Verify the path is currently a mount point
if ! findmnt -M "$FOLDER" >/dev/null 2>&1; then
    echo "Error: $FOLDER is not currently mounted."
    exit 1
fi

# Get the mounted source device
DEVICE=$(findmnt -n -o SOURCE -M "$FOLDER")

echo "Mounted device: $DEVICE"

# Get filesystem UUID if available
UUID=$(sudo blkid -s UUID -o value "$DEVICE" 2>/dev/null || true)

if [ -n "$UUID" ]; then
    echo "Filesystem UUID: $UUID"
else
    echo "Warning: Could not determine filesystem UUID."
fi

# Unmount
echo "Unmounting $FOLDER..."
sudo umount "$FOLDER"

# Back up /etc/fstab
FSTAB_BACKUP="/etc/fstab.backup.before.remove.$(date +%Y%m%d%H%M%S)"

echo "Backing up /etc/fstab to:"
echo "$FSTAB_BACKUP"

sudo cp /etc/fstab "$FSTAB_BACKUP"

# Remove matching fstab entry.
# Prefer matching both UUID and mount path.
if [ -n "$UUID" ] && grep -Eq "^[[:space:]]*UUID=$UUID[[:space:]]+$FOLDER[[:space:]]" /etc/fstab; then
    echo "Removing UUID=$UUID mounted at $FOLDER from /etc/fstab..."

    sudo sed -i "\|^[[:space:]]*UUID=$UUID[[:space:]]\+$FOLDER[[:space:]]|d" /etc/fstab

elif grep -Eq "^[^#].*[[:space:]]$FOLDER[[:space:]]" /etc/fstab; then
    echo "Removing mount entry for $FOLDER from /etc/fstab..."

    sudo sed -i "\|^[^#].*[[:space:]]$FOLDER[[:space:]]|d" /etc/fstab

else
    echo "No matching /etc/fstab entry found."
fi

sudo systemctl daemon-reload

# Remove mount directory only if empty
if [ -d "$FOLDER" ]; then
    if [ -z "$(ls -A "$FOLDER")" ]; then
        echo "Removing empty mount directory $FOLDER..."
        sudo rmdir "$FOLDER"
    else
        echo "Warning: $FOLDER is not empty."
        echo "Directory will not be removed."
    fi
fi

echo "=============================================="
echo "Mount removed successfully."
echo ""
echo "Disk data has NOT been erased."
echo "Disk has NOT been detached from Google Cloud."
echo "=============================================="

lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS,MODEL
