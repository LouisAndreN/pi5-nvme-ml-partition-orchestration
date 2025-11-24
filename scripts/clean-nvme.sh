NVME_DEVICE=$(detect_nvme_device)
NVME_PATH="/dev/${NVME_DEVICE}"

for part in $(lsblk -ln -o NAME "${NVME_PATH}" | tail -n +2); do
    if mountpoint -q "/dev/${part}" then
        sudo umount -f "/dev/${part}"
    fi
done

sudo wipefs -a "${NVME_PATH}"
