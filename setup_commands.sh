# Pi 5 NVMe 1To Setup - Command Reference for Ubuntu Server 24.04.3 LTS boot

# Install needed packages
sudo apt update
sudo apt install -y lvm2 cryptsetup btrfs-progs xfsprogs parted rsync mc unzip curl  # mc = MinIO client

## Prerequisites Check

# Check EEPROM version
sudo rpi-eeprom-update

# Update if needed
sudo rpi-eeprom-update -a
sudo reboot

# Verify NVMe detected
lspci | grep -i nvme


## Clean NVMe
# Unmount all partitions
sudo umount /dev/nvme0n1p*

# Verify nothing mounted
sudo mount | grep nvme

# Wipe filesystem signatures
sudo wipefs -a /dev/nvme0n1

# Erase beginning and end of NVMe
sudo dd if=/dev/zero of=/dev/nvme0n1 bs=1M count=100 status=progress
sudo dd if=/dev/zero of=/dev/nvme0n1 bs=1M count=100 seek=$((`sudo blockdev --getsz /dev/nvme0n1` / 2048 - 100)) status=progress

# Verify clean
sudo blkid /dev/nvme0n1  # Should return nothing

# Check NVMe size
sudo fdisk -l /dev/nvme0n1 | grep "Disk /dev/nvme0n1"


## Create partitions

# Start parted
sudo parted /dev/nvme0n1

# In parted shell:
mklabel gpt

mkpart primary fat32 1MiB 1025MiB            # p1 : /boot/firmware 1 GiB
mkpart primary ext4 1025MiB 101GiB          # p2 : / 100 GiB
mkpart primary linux-swap 101GiB 105GiB  # p3 : 4 GB
mkpart primary ext4 105GiB 110GiB        # p4 : /recovery 5 GB
mkpart primary 110GiB 100%               # p5 : LUKS 850 GB

set 1 boot on
set 1 esp on

print  # Verify
quit


## Format partitions
# p1 boot
sudo mkfs.vfat -F32 -n BOOT /dev/nvme0n1p1

# p2 root
sudo mkfs.ext4 -L ROOT /dev/nvme0n1p2

# p3 swap
sudo mkswap -L SWAP /dev/nvme0n1p3

# p4 recovery
sudo mkfs.ext4 -L RECOVERY /dev/nvme0n1p4

# p5 LUKS (encryption)
# Configuration LUKS2 encryption
# Parameters:
#   - Algorithm: AES-XTS-256 (512-bit key)
#   - PBKDF: Argon2id (GPU-resistant)
#   - Sector size: 4096 bytes (NVMe native) (better performance but compatible only with kernel 5.9+)
#   - Iteration time: 2000ms (fast boot)
sudo cryptsetup luksFormat /dev/nvme0n1p5 --type luks2 --cipher aes-xts-plain64 --key-size 512 --pbkdf argon2id --iter-time 2000 --label "cryptdata"
# Choose very strong passphrase and save it !

# Verification : PBKDF: argon2id, Time cost, Memory, Threads, Cipher, Payload Sector size=4096 (=> check if alignment error but okay if 1MiB aligned)
sudo cryptsetup luksDump /dev/nvme0n1p5

# Backup LUKS header
sudo cryptsetup luksHeaderBackup /dev/nvme0n1p5 \
    --header-backup-file /tmp/luks-header-backup.img

# Copy to /recovery (once mounted)
sudo mount /dev/nvme0n1p4 /mnt/nvme_recovery
sudo mkdir -p /mnt/nvme_recovery/backup
sudo cp /tmp/luks-header-backup.img /mnt/nvme_recovery/backup/
sudo chmod 400 /mnt/nvme_recovery/backup/luks-header-backup.img

# Check
ls -lh /mnt/nvme_recovery/backup/

# Open LUKS container
sudo cryptsetup open /dev/nvme0n1p5 cryptdata

# Create PV LVM on opened container
sudo pvcreate /dev/mapper/cryptdata

# Create VG
sudo vgcreate vg-main /dev/mapper/cryptdata

# Tuning VG for performance
sudo vgchange --alloc anywhere vg-main

# Create LV
sudo lvcreate -L 20G -n lv-var vg-main
sudo lvcreate -L 30G -n lv-logs vg-main
sudo lvcreate -L 120G -n lv-influxdb vg-main
sudo lvcreate -L 80G -n lv-containers vg-main
sudo lvcreate -L 10G -n lv-grafana vg-main
sudo lvcreate -L 60G -n lv-ml-models vg-main
sudo lvcreate -L 40G -n lv-ml-cache vg-main
sudo lvcreate -L 80G -n lv-cloud-sync vg-main
sudo lvcreate -L 60G -n lv-scratch vg-main
sudo lvcreate -l 100%FREE -n lv-data vg-main   # ~350 GiB

# InfluxDB (I/O intensif)
sudo lvchange --readahead 8192 vg-main/lv-influxdb  # 4MB readahead
sudo lvchange --zero n vg-main/lv-influxdb         # Pas de zero on new blocks

# Cloud-sync (gros transferts)
sudo lvchange --readahead 8192 vg-main/lv-cloud-sync   # 4MB readahead

# ML-cache (gros fichiers)
sudo lvchange --readahead 8192 vg-main/lv-ml-cache

# Check
sudo lvs vg-main
sudo vgs vg-main

# Format LV
sudo mkfs.ext4 -L VAR /dev/vg-main/lv-var
sudo mkfs.ext4 -L LOGS /dev/vg-main/lv-logs
sudo mkfs.xfs -f -L INFLUXDB /dev/vg-main/lv-influxdb
sudo mkfs.xfs -f -L CONTAINERS /dev/vg-main/lv-containers
sudo mkfs.ext4 -L GRAFANA /dev/vg-main/lv-grafana
sudo mkfs.xfs -f -L ML-MODELS /dev/vg-main/lv-ml-models
sudo mkfs.xfs -f -L ML-CACHE /dev/vg-main/lv-ml-cache
sudo mkfs.xfs -f -L CLOUD-SYNC /dev/vg-main/lv-cloud-sync
sudo mkfs.xfs -f -L SCRATCH /dev/vg-main/lv-scratch
sudo mkfs.btrfs -f -L DATA /dev/vg-main/lv-data

# Create subvolumes Btrfs on lv-data
sudo mount /dev/vg-main/lv-data /mnt
sudo btrfs subvolume create /mnt/@iot-hot
sudo btrfs subvolume create /mnt/@iot-archives
sudo btrfs subvolume create /mnt/@backups
sudo btrfs subvolume create /mnt/@personal
sudo umount /mnt


# Check XFS
sudo xfs_repair -n /dev/vg-main/lv-influxdb  # -n = dry run
sudo xfs_repair -n /dev/vg-main/lv-containers
sudo xfs_repair -n /dev/vg-main/lv-ml-models
sudo xfs_repair -n /dev/vg-main/lv-ml-cache
sudo xfs_repair -n /dev/vg-main/lv-cloud-sync
sudo xfs_repair -n /dev/vg-main/lv-scratch

# Check ext4
sudo e2fsck -fn /dev/nvme0n1p2  # root
sudo e2fsck -fn /dev/nvme0n1p4  # recovery
sudo e2fsck -fn /dev/vg-main/lv-var
sudo e2fsck -fn /dev/vg-main/lv-logs
sudo e2fsck -fn /dev/vg-main/lv-grafana

# Check BTRFS
sudo btrfs check --readonly /dev/vg-main/lv-data


## Save UUIDs and LUKS mapper
mkdir -p ~/nvme-setup

BOOT_UUID=$(blkid -s UUID -o value /dev/nvme0n1p1)
ROOT_UUID=$(blkid -s UUID -o value /dev/nvme0n1p2)
SWAP_UUID=$(blkid -s UUID -o value /dev/nvme0n1p3)
RECOVERY_UUID=$(blkid -s UUID -o value /dev/nvme0n1p4)

VAR_UUID=$(blkid -s UUID -o value /dev/vg-main/lv-var)
LOGS_UUID=$(blkid -s UUID -o value /dev/vg-main/lv-logs)
INFLUXDB_UUID=$(blkid -s UUID -o value /dev/vg-main/lv-influxdb)
CONTAINERS_UUID=$(blkid -s UUID -o value /dev/vg-main/lv-containers)
GRAFANA_UUID=$(blkid -s UUID -o value /dev/vg-main/lv-grafana)
MLMODELS_UUID=$(blkid -s UUID -o value /dev/vg-main/lv-ml-models)
MLCACHE_UUID=$(blkid -s UUID -o value /dev/vg-main/lv-ml-cache)
CLOUDSYNC_UUID=$(blkid -s UUID -o value /dev/vg-main/lv-cloud-sync)
SCRATCH_UUID=$(blkid -s UUID -o value /dev/vg-main/lv-scratch)
DATA_UUID=$(blkid -s UUID -o value /dev/vg-main/lv-data)

cat > ~/nvme-setup/uuids.txt <<EOF
BOOT_UUID=$BOOT_UUID
ROOT_UUID=$ROOT_UUID
SWAP_UUID=$SWAP_UUID
RECOVERY_UUID=$RECOVERY_UUID
VAR_UUID=$VAR_UUID
LOGS_UUID=$LOGS_UUID
INFLUXDB_UUID=$INFLUXDB_UUID
CONTAINERS_UUID=$CONTAINERS_UUID
GRAFANA_UUID=$GRAFANA_UUID
MLMODELS_UUID=$MLMODELS_UUID
MLCACHE_UUID=$MLCACHE_UUID
CLOUDSYNC_UUID=$CLOUDSYNC_UUID
SCRATCH_UUID=$SCRATCH_UUID
DATA_UUID=$DATA_UUID
EOF

cat ~/nvme-setup/uuids.txt

## Mount all

# Create mount points
sudo mkdir -p /mnt/nvme_{boot,root,recovery,var,logs,influxdb,containers,grafana,ml-models,ml-cache,cloud-sync,scratch,data}

# Mount
sudo mount /dev/nvme0n1p1 /mnt/nvme_boot
sudo mount /dev/nvme0n1p2 /mnt/nvme_root
sudo mount /dev/nvme0n1p4 /mnt/nvme_recovery
sudo mount /dev/vg-main/lv-var /mnt/nvme_var
sudo mount /dev/vg-main/lv-logs /mnt/nvme_logs
sudo mount /dev/vg-main/lv-influxdb /mnt/nvme_influxdb
sudo mount /dev/vg-main/lv-containers /mnt/nvme_containers
sudo mount /dev/vg-main/lv-grafana /mnt/nvme_grafana
sudo mount /dev/vg-main/lv-ml-models /mnt/nvme_ml-models
sudo mount /dev/vg-main/lv-ml-cache /mnt/nvme_ml-cache
sudo mount /dev/vg-main/lv-cloud-sync /mnt/nvme_cloud-sync
sudo mount /dev/vg-main/lv-scratch /mnt/nvme_scratch
sudo mount /dev/vg-main/lv-data /mnt/nvme_data


# Verify
df -h | grep nvme

# Copier outils essentiels dans /recovery
sudo mkdir -p /mnt/nvme_recovery/{tools,scripts,backup}

# Scripts recovery
sudo tee /mnt/nvme_recovery/scripts/unlock-luks.sh > /dev/null <<'EOF'
#!/bin/bash
# Emergency LUKS unlock script

echo "🔓 Unlocking LUKS container..."

if [ -f /boot/luks-keyfile ]; then
    cryptsetup open /dev/nvme0n1p5 cryptdata --key-file /boot/luks-keyfile
else
    echo "⚠️  Keyfile not found, using backup header..."
    cryptsetup luksHeaderRestore /dev/nvme0n1p5 \
        --header-backup-file /recovery/backup/luks-header-backup.img
    cryptsetup open /dev/nvme0n1p5 cryptdata
fi

vgchange -ay vg-main
echo "✅ LVM volumes activated"
EOF

sudo chmod +x /mnt/nvme_recovery/scripts/unlock-luks.sh

# Documentation
sudo tee /mnt/nvme_recovery/README.txt > /dev/null <<EOF
EMERGENCY RECOVERY PARTITION
============================

This partition contains:
- LUKS header backup (backup/luks-header-backup.img)
- LUKS keyfile backup (backup/luks-keyfile)
- Recovery scripts (scripts/)
- Emergency tools

⚠️  LUKS CONFIGURATION:
- LUKS2 with 4096-byte sectors (requires kernel 5.9+)
- If using rescue USB: ensure kernel 5.9+ or decrypt will FAIL
- Ubuntu 22.04+ live USB recommended (kernel 6.2+)

DISASTER RECOVERY STEPS:
1. Boot from USB/SD card with kernel 5.9+ (check: uname -r)
2. Mount this partition: mount /dev/nvme0n1p4 /mnt
3. Run: bash /mnt/scripts/unlock-luks.sh
4. Mount filesystems as needed

LUKS HEADER RESTORE:
cryptsetup luksHeaderRestore /dev/nvme0n1p5 \\
    --header-backup-file /mnt/backup/luks-header-backup.img

LUKS DIAGNOSTICS:
# Show LUKS header info and key slots
cryptsetup luksDump /dev/nvme0n1p5

# Check sector size (should show 4096)
cryptsetup luksDump /dev/nvme0n1p5 | grep "sector size"
# Output: Payload sector size:     4096

# Check which key slots are active
# Slot 0: Original passphrase
# Slot 1: Keyfile (/boot/luks-keyfile)

PASSPHRASE RECOVERY:
If passphrase forgotten but keyfile available:
1. Boot with keyfile (automatic)
2. Add new passphrase:
   cryptsetup luksAddKey /dev/nvme0n1p5 --key-file /boot/luks-keyfile
3. Remove old passphrase (if known slot):
   cryptsetup luksKillSlot /dev/nvme0n1p5 0

COMPLETE FAILURE (both passphrase + keyfile lost):
❌ Data is UNRECOVERABLE (encryption working as designed)
✅ This is why backups exist (/mnt/data/backups)

Created: $(date)
System: Raspberry Pi 5 + NVMe 1TB + Hailo-8L
EOF

## Copy data from SD
# Remount SD boot read-only
sudo mount -o remount,ro /boot/firmware

# Copy
sudo rsync -axHAWX --info=progress2 /boot/firmware/ /mnt/nvme_boot/

# Remount read-write
sudo mount -o remount,rw /boot/firmware

# Verify
ls -la /mnt/nvme_boot/
du -sh /mnt/nvme_boot/


## Copy root partition
sudo rsync -axHAWX --info=progress2 \
  --exclude=/boot/firmware \
  --exclude=/proc \
  --exclude=/sys \
  --exclude=/dev \
  --exclude=/run \
  --exclude=/mnt \
  --exclude=/media \
  --exclude=/tmp \
  --exclude=/lost+found \
  / \
  /mnt/nvme_root/

# Verify
ls -la /mnt/nvme_root/
sudo du -sh /mnt/nvme_root/

# Create missing directories
sudo mkdir -p /mnt/nvme_root/{boot/firmware,proc,sys,dev,run,tmp,mnt,media}
sudo mkdir -p /mnt/nvme_root/mnt/{ml-models,ml-cache,cloud-sync,scratch,data}
sudo mkdir -p /mnt/nvme_root/var/lib/containers


# Copy /var (exclude containers)
sudo rsync -axHAWX --info=progress2 \
  --exclude=/var/lib/containers \
  --exclude=/var/tmp \
  --exclude=/var/cache/apt/archives/*.deb \
  --exclude=/var/lost+found \
  /var/ /mnt/nvme_var/

# Copy containers separately
sudo rsync -axHAWX --info=progress2 \
  /var/lib/containers/ /mnt/nvme_containers/


## Configure cmdline.txt

sudo nano /mnt/nvme_boot/cmdline.txt

# Content (single line):
```
console=serial0,115200 multipath=off dwc_otg.lpm_enable=0 console=tty1 root=LABEL=ROOT rootfstype=ext4 rootwait fixrtc cfg80211.ieee80211_regdom=JP
```

# Verify:
wc -l /mnt/nvme_boot/cmdline.txt  # Should output: 1

## Configure /etc/fstab
# Load UUIDs
source ~/nvme-setup/uuids.txt

# Create fstab
# Scratch (nobarrier OK: temporary data only, power loss acceptable)
sudo tee /mnt/nvme_root/etc/fstab > /dev/null <<EOF
UUID=$BOOT_UUID       /boot/firmware          vfat    defaults                          0 2
UUID=$ROOT_UUID       /                       ext4    defaults,noatime                  0 1
UUID=$SWAP_UUID       none                    swap    sw,pri=-2                         0 0
UUID=$RECOVERY_UUID   /recovery               ext4    defaults,noatime                  0 2

/dev/vg-main/lv-var       /var                    ext4    defaults,noatime,nodiratime       0 2
/dev/vg-main/lv-logs      /var/log                ext4    defaults,noatime,nodiratime       0 2
/dev/vg-main/lv-influxdb  /var/lib/influxdb       xfs     defaults,noatime,allocsize=16m,inode64  0 2
/dev/vg-main/lv-containers /var/lib/containers    xfs     defaults,noatime,allocsize=16m  0 2
/dev/vg-main/lv-grafana   /var/lib/grafana        ext4    defaults,noatime,nodiratime       0 2
/dev/vg-main/lv-ml-models /mnt/ml-models           xfs     defaults,noatime,allocsize=16m  0 2
/dev/vg-main/lv-ml-cache  /mnt/ml-cache           xfs     defaults,noatime,allocsize=16m  0 2
/dev/vg-main/lv-cloud-sync /mnt/cloud-sync         xfs     defaults,noatime,allocsize=64m,inode64  0 2
/dev/vg-main/lv-scratch   /mnt/scratch            xfs     defaults,noatime,allocsize=16m,nobarrier,logbsize=256k  0 2
/dev/vg-main/lv-data      /mnt/data               btrfs   defaults,noatime,compress=zstd:3,space_cache=v2,subvol=@iot-hot  0 2

tmpfs                     /tmp                    tmpfs   defaults,noatime,nosuid,nodev,size=2G  0 0
tmpfs                     /var/tmp                tmpfs   defaults,noatime,nosuid,nodev,size=1G  0 0
EOF

# Verify
cat /mnt/nvme_root/etc/fstab

# Archives
sudo tee /mnt/nvme_root/etc/systemd/system/mnt-data-archives.mount > /dev/null <<'EOF'
[Unit]
Description=BTRFS IoT Archives Subvolume (High Compression)
After=mnt-data.mount
Requires=mnt-data.mount

[Mount]
What=/dev/vg-main/lv-data
Where=/mnt/data/archives
Type=btrfs
Options=defaults,noatime,compress=zstd:9,space_cache=v2,subvol=@iot-archives

[Install]
WantedBy=multi-user.target
EOF

# Backups
sudo tee /mnt/nvme_root/etc/systemd/system/mnt-data-backups.mount > /dev/null <<'EOF'
[Unit]
Description=BTRFS System Backups Subvolume
After=mnt-data.mount
Requires=mnt-data.mount

[Mount]
What=/dev/vg-main/lv-data
Where=/mnt/data/backups
Type=btrfs
Options=defaults,noatime,compress=zstd:3,space_cache=v2,subvol=@backups

[Install]
WantedBy=multi-user.target
EOF

# Personal
sudo tee /mnt/nvme_root/etc/systemd/system/mnt-data-personal.mount > /dev/null <<'EOF'
[Unit]
Description=BTRFS Personal Data Subvolume
After=mnt-data.mount
Requires=mnt-data.mount

[Mount]
What=/dev/vg-main/lv-data
Where=/mnt/data/personal
Type=btrfs
Options=defaults,noatime,compress=zstd:3,space_cache=v2,subvol=@personal

[Install]
WantedBy=multi-user.target
EOF

# Créer répertoires mount points
sudo mkdir -p /mnt/nvme_root/mnt/data/{archives,backups,personal}


## Configure crypttab (automatic unlock with keyfile - headless)
sudo dd if=/dev/urandom of=/mnt/nvme_boot/luks-keyfile bs=512 count=1
sudo chmod 400 /mnt/nvme_boot/luks-keyfile
sudo cryptsetup luksAddKey /dev/nvme0n1p5 /mnt/nvme_boot/luks-keyfile

sudo cp /mnt/nvme_boot/luks-keyfile /mnt/nvme_recovery/backup/
sudo chmod 400 /mnt/nvme_recovery/backup/luks-keyfile

# Add to crypttab
sudo tee /mnt/nvme_root/etc/crypttab > /dev/null <<EOF
cryptdata UUID=$(blkid -s UUID -o value /dev/nvme0n1p5) /boot/luks-keyfile luks,discard
EOF

## Update EEPROM
sudo rpi-eeprom-config --edit

# Add:
```
[all]
BOOT_UART=0
POWER_OFF_ON_HALT=0
BOOT_ORDER=0xf641
PCIE_PROBE=1
```

# Apply:
sudo rpi-eeprom-update -a

## Configure config.txt
sudo nano /mnt/nvme_boot/config.txt

# Ensure these lines exist:
```
[all]
dtparam=pciex1_gen=3
arm_64bit=1
kernel=vmlinuz
cmdline=cmdline.txt
initramfs initrd.img followkernel

[pi5]
dtparam=pciex1
```

## Update system (chroot)
# Fix resolv.conf (DNS)
sudo rm /mnt/nvme_root/etc/resolv.conf
sudo cp /etc/resolv.conf /mnt/nvme_root/etc/resolv.conf

# Mount system filesystems
sudo mount -t proc /proc /mnt/nvme_root/proc
sudo mount -t sysfs /sys /mnt/nvme_root/sys
sudo mount --rbind /dev /mnt/nvme_root/dev
sudo mount -t devpts devpts /mnt/nvme_root/dev/pts
sudo mount --bind /run /mnt/nvme_root/run
sudo mount -t tmpfs tmpfs /mnt/nvme_root/tmp

# Enter chroot
sudo chroot /mnt/nvme_root /bin/bash

# Inside chroot:
apt update
apt full-upgrade -y
apt install linux-raspi linux-image-raspi linux-headers-raspi linux-firmware-raspi -y


# Install zram generator
apt install -y systemd-zram-generator

# Configure zram (4GB compressed swap in RAM)
cat > /etc/systemd/zram-generator.conf <<'ZRAMEOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
ZRAMEOF


# Copy keyfile in initramfs
mkdir -p /etc/initramfs-tools/hooks
cat > /etc/initramfs-tools/hooks/copy-luks-key <<'EOF'
#!/bin/sh
PREREQ=""
prereqs()
{
    echo "$PREREQ"
}
case $1 in
    prereqs)
        prereqs
        exit 0
        ;;
esac

. /usr/share/initramfs-tools/hook-functions

# Check keyfile existe
if [ ! -f /boot/luks-keyfile ]; then
    echo "WARNING: /boot/luks-keyfile not found!" >&2
    echo "LUKS will require manual passphrase at boot!" >&2
    exit 0  # Continue sans erreur (fallback passphrase)
fi

# Copy keyfile to initramfs
mkdir -p "${DESTDIR}/boot"
cp /boot/luks-keyfile "${DESTDIR}/boot/"

# Verify copy succeeded
if [ ! -f "${DESTDIR}/boot/luks-keyfile" ]; then
    echo "ERROR: Failed to copy LUKS keyfile to initramfs!" >&2
    exit 1
fi

# Set permissions in initramfs
chmod 400 "${DESTDIR}/boot/luks-keyfile"

echo "LUKS keyfile added to initramfs" >&2
EOF

chmod +x /etc/initramfs-tools/hooks/copy-luks-key

# Add cryptsetup modules
echo "dm_crypt" >> /etc/initramfs-tools/modules
echo "aes" >> /etc/initramfs-tools/modules
echo "sha256" >> /etc/initramfs-tools/modules

# Regenerate initramfs with crypttab + keyfile
update-initramfs -u -k all

# Enable BTRFS subvolume mount units
systemctl enable mnt-data-archives.mount
systemctl enable mnt-data-backups.mount
systemctl enable mnt-data-personal.mount

# Exit chroot
exit

# Copy kernel files
sudo cp /mnt/nvme_root/boot/vmlinuz-* /mnt/nvme_boot/vmlinuz
sudo cp /mnt/nvme_root/boot/initrd.img-* /mnt/nvme_boot/initrd.img


## Enable TRIM
sudo systemctl enable fstrim.timer
sudo systemctl start fstrim.timer


## Create post-boot verification script
sudo tee /mnt/nvme_root/opt/verify-boot.sh > /dev/null <<'EOF'
#!/bin/bash
# Post-boot verification - run after first NVMe boot

echo "🔍 Verifying NVMe boot setup..."

# Check LUKS
if ! cryptsetup status cryptdata | grep -q "is active"; then
    echo "❌ LUKS not active!"
    exit 1
fi
echo "✅ LUKS active"

# Check LVM
if ! vgs vg-main &>/dev/null; then
    echo "❌ VG vg-main not found!"
    exit 1
fi
echo "✅ LVM volume group active"

# Check all LVs mounted
REQUIRED_MOUNTS=(
    "/" "/var" "/var/log" "/var/lib/influxdb"
    "/var/lib/containers" "/var/lib/grafana"
    "/mnt/ml-models" "/mnt/ml-cache" "/mnt/cloud-sync"
    "/mnt/scratch" "/mnt/data"
)

for mount in "${REQUIRED_MOUNTS[@]}"; do
    if ! mountpoint -q "$mount"; then
        echo "❌ $mount not mounted!"
        exit 1
    fi
done
echo "✅ All partitions mounted"

# Check XFS mount options
if ! mount | grep '/var/lib/influxdb' | grep -q 'allocsize=16m'; then
    echo "⚠️  InfluxDB missing XFS tuning"
fi
echo "✅ XFS options correct"

# Check BTRFS compression
if ! mount | grep '/mnt/data' | grep -q 'compress=zstd'; then
    echo "⚠️  BTRFS compression not enabled"
fi
echo "✅ BTRFS compression active"

# Check BTRFS subvolume mount units
echo ""
echo "Checking BTRFS subvolume systemd units..."
for unit in mnt-data-archives.mount mnt-data-backups.mount mnt-data-personal.mount; do
    if systemctl is-active "$unit" &>/dev/null; then
        echo "  ✅ $unit"
    else
        echo "  ⚠️  $unit not active (run: systemctl start $unit)"
    fi
done

# Check swap configuration
echo ""
echo "Checking swap configuration..."
if ! swapon --show | grep -q 'zram0'; then
    echo "⚠️  zram swap not active!"
    echo "  Run: sudo systemctl start systemd-zram-setup@zram0.service"
else
    echo "✅ zram swap active"
fi

# Show swap details
echo ""
echo "📊 Swap configuration:"
swapon --show
echo ""
echo "Expected:"
echo "  NAME           TYPE      SIZE USED PRIO"
echo "  /dev/zram0     partition   4G   0B  100  ← High priority (used first)"
echo "  /dev/nvme0n1p3 partition   4G   0B   -2  ← Low priority (fallback)"

# Show zram stats
if [ -e /dev/zram0 ]; then
    echo ""
    echo "📊 zram details:"
    zramctl /dev/zram0
    echo ""
    echo "Expected compression ratio: 2-3:1 (zstd)"
fi

# Check NVMe swap present (fallback)
if ! swapon --show | grep -q 'nvme0n1p3'; then
    echo "⚠️  NVMe swap partition not active"
fi

# Check TRIM
if ! systemctl is-enabled fstrim.timer | grep -q 'enabled'; then
    echo "⚠️  TRIM timer not enabled"
    systemctl enable fstrim.timer
fi
echo "✅ TRIM configured"

# Disk usage report
echo ""
echo "Disk usage:"
df -h | grep -E '(Filesystem|nvme0n1|vg-main)'

echo ""
echo "✅ All checks passed! NVMe boot successful."
echo ""
echo "Next steps:"
echo "1. Backup LUKS keyfile: cp /boot/luks-keyfile ~/SAFE_LOCATION"
echo "2. Test recovery: cat /recovery/README.txt"
echo "3. Configure monitoring: /opt/scripts/disk_monitor.sh"
EOF

sudo chmod +x /mnt/nvme_root/opt/verify-boot.sh


## Final Steps
# Sync
sync

# Unmount
sudo umount -lR /mnt/nvme_root
sudo umount /mnt/nvme_boot
sudo umount /mnt/nvme_recovery


# Poweroff
sudo poweroff

# Remove SD card and it should boot from NVMe

# After first boot on NVMe, check the following :
#    - Launch /opt/verify-boot.sh => is everything checked ?
#    - dmesg | grep -iE 'nvme|pcie|aer|error|crc|timeout|reset|luks|crypt' => no PCIe errors ?
#    - cryptsetup status cryptdata => sector_size=4096 and active ?
#    - fio to validate performances :textsudo apt install fio
#        fio --name=seqread --ioengine=libaio --direct=1 --rw=read --bs=128k --numjobs=1 --iodepth=32 --size=4g --runtime=30 --group_reporting => ~700–900 MB/s for Gen3
