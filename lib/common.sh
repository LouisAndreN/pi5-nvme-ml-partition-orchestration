detect_nvme_device() {
    sudo lsblk -d -o NAME,TYPE | grep nvme | awk '{print $1}' | head -1
}
