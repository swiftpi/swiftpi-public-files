#!/bin/bash
# This script is used to mount purchased disks to vm.
# Before executing this script, make sure disks are already attached to the vm. This can be done on web console in vm's details.
set -euo pipefail


# Check if arguments were passed
if [ $# -gt 0 ]; then
    DISK_NAMES=("$@")
else
    echo "Error: No disk names provided. Please pass disk names as arguments."
    echo "Example: bash vm-mount-disk-script.sh disk-apps disk-databases"
    exit 0
fi

echo "=== Current Attached Disks ==="
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS,MODEL
echo "=============================="
echo "Target disks to process: ${DISK_NAMES[*]}"
echo "=============================="

# Loop through each disk name
for DISKNAME in "${DISK_NAMES[@]}"; do
    DISK="/dev/disk/by-id/google-$DISKNAME"
    FOLDER="/opt/$DISKNAME"

    echo "--------------------------------------------------"
    echo "Processing: $DISKNAME -> Target: $FOLDER"
    echo "--------------------------------------------------"

    # Safety Check: Verify the Google Cloud disk symlink actually exists
    if [ ! -L "$DISK" ]; then
        echo "Skipping: Symlink $DISK does not exist. (Disk not attached to VM)"
        continue
    fi

    # Resolve actual device path
    REAL_DEV=$(readlink -f "$DISK")
    echo "Disk $DISKNAME points to device: $REAL_DEV"
    lsblk -f "$REAL_DEV"

    # Safety Check: Prevent accidental data loss if a filesystem already exists
    if sudo blkid -s TYPE -o value "$DISK" >/dev/null 2>&1; then
        echo "WARNING: $DISK already has a filesystem! Skipping formatting to prevent data loss."
        
        # Ensure it is mounted
        if ! findmnt "$FOLDER" >/dev/null 2>&1; then
            echo "Ensuring directory exists and attempting to mount existing filesystem..."
            sudo mkdir -p "$FOLDER"
            if ! grep -q "$FOLDER" /etc/fstab; then
                UUID=$(sudo blkid -s UUID -o value "$DISK")
                sudo cp /etc/fstab "/etc/fstab.backup.before.$DISKNAME"
                echo "UUID=$UUID $FOLDER ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
            fi
            sudo systemctl daemon-reload
            sudo mount -a
        fi
        continue
    fi

    # 3. Format the entire disk
    echo "Formatting $DISK with ext4..."
    sudo mkfs.ext4 -m 0 -E lazy_itable_init=0,lazy_journal_init=0,discard "$DISK"

    # 4. Create the mount directory
    sudo mkdir -p "$FOLDER"

    # 5. Mount the disk temporarily to verify
    sudo mount "$DISK" "$FOLDER"
    echo "Temporary mount check:"
    findmnt "$FOLDER"

    # 6. Get the filesystem UUID
    UUID=$(sudo blkid -s UUID -o value "$DISK")
    echo "Generated UUID: $UUID"

    # 7. Back up /etc/fstab
    sudo cp /etc/fstab "/etc/fstab.backup.before.$DISKNAME"

    # 8. Add the automatic mount configuration if not already present
    if ! grep -q "$FOLDER" /etc/fstab; then
        echo "UUID=$UUID $FOLDER ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
    fi

    # 9. Test the /etc/fstab configuration
    echo "Testing fstab persistence..."
    sudo umount "$FOLDER"
    sudo systemctl daemon-reload
    sudo mount -a

    # 10. Final Verification
    echo "Success! Final mount status for $FOLDER:"
    findmnt "$FOLDER"
    df -hT "$FOLDER"
    
done

echo "=============================================="
echo "Requested disks processed successfully!"
echo "=============================================="
