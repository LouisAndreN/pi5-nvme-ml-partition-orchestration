# Pi 5 NVMe Setup - Command Reference for Ubuntu Server 24.04 LTS boot

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
mount | grep nvme

# Wipe filesystem signatures
sudo wipefs -a /dev/nvme0n1

# Verify clean
sudo blkid /dev/nvme0n1  # Should return nothing

# Check NVMe size
sudo fdisk -l /dev/nvme0n1 | grep "Disk /dev/nvme0n1"


## Create partitions

# Start parted
sudo parted /dev/nvme0n1

# In parted shell:
mklabel gpt

mkpart primary fat32 1MiB 1025MiB
mkpart primary ext4 1025MiB 101GiB
mkpart primary ext4 101GiB 241GiB
mkpart primary ext4 241GiB 421GiB
mkpart primary ext4 421GiB 651GiB
mkpart primary xfs 651GiB 711GiB
mkpart primary btrfs 711GiB 100%

set 1 boot on
set 1 esp on

print  # Verify
quit

## Format partitions
sudo mkfs.vfat -F32 -n system-boot /dev/nvme0n1p1
sudo mkfs.ext4 -L writable /dev/nvme0n1p2
sudo mkfs.ext4 /dev/nvme0n1p3
sudo mkfs.ext4 -L CONTAINERS /dev/nvme0n1p4
sudo mkfs.ext4 -L ML-DATA /dev/nvme0n1p5
sudo mkfs.xfs -f /dev/nvme0n1p6
sudo mkfs.btrfs -f -L DATA /dev/nvme0n1p7

# Verify
lsblk -f /dev/nvme0n1


## Save UUIDs

# Get UUIDs
BOOT_UUID=$(sudo blkid -s UUID -o value /dev/nvme0n1p1)
ROOT_UUID=$(sudo blkid -s UUID -o value /dev/nvme0n1p2)
VAR_UUID=$(sudo blkid -s UUID -o value /dev/nvme0n1p3)
CONTAINERS_UUID=$(sudo blkid -s UUID -o value /dev/nvme0n1p4)
ML_DATA_UUID=$(sudo blkid -s UUID -o value /dev/nvme0n1p5)
SCRATCH_UUID=$(sudo blkid -s UUID -o value /dev/nvme0n1p6)
DATA_UUID=$(sudo blkid -s UUID -t TYPE=btrfs /dev/nvme0n1p7 -o value)

# Save to file
mkdir -p ~/nvme-setup
cat > ~/nvme-setup/uuids.txt <<EOF
BOOT_UUID=$BOOT_UUID
ROOT_UUID=$ROOT_UUID
VAR_UUID=$VAR_UUID
CONTAINERS_UUID=$CONTAINERS_UUID
ML_DATA_UUID=$ML_DATA_UUID
SCRATCH_UUID=$SCRATCH_UUID
DATA_UUID=$DATA_UUID
EOF

# Verify
cat ~/nvme-setup/uuids.txt

## Mount all

# Create mount points
sudo mkdir -p /mnt/nvme_{boot,root,var,containers,ml,scratch,data}

# Mount
sudo mount /dev/nvme0n1p1 /mnt/nvme_boot
sudo mount /dev/nvme0n1p2 /mnt/nvme_root
sudo mount /dev/nvme0n1p3 /mnt/nvme_var
sudo mount /dev/nvme0n1p4 /mnt/nvme_containers
sudo mount /dev/nvme0n1p5 /mnt/nvme_ml
sudo mount /dev/nvme0n1p6 /mnt/nvme_scratch
sudo mount /dev/nvme0n1p7 /mnt/nvme_data

# Verify
df -h | grep nvme

## Copy boot partition
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
sudo mkdir -p /mnt/nvme_root/mnt/{ml-data,scratch,data}
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
console=serial0,115200 multipath=off dwc_otg.lpm_enable=0 console=tty1 root=LABEL=writable rootfstype=ext4 rootwait fixrtc cfg80211.ieee80211_regdom=JP
```

Verify:
wc -l /mnt/nvme_boot/cmdline.txt  # Should output: 1

## Configure fstab
# Load UUIDs
source ~/nvme-setup/uuids.txt

# Create fstab
sudo tee /mnt/nvme_root/etc/fstab > /dev/null <<EOF
UUID=$BOOT_UUID  /boot/firmware  vfat  defaults  0  2
UUID=$ROOT_UUID  /  ext4  defaults,noatime  0  1

UUID=$VAR_UUID  /var  ext4  defaults,noatime,barrier=1  0  2
UUID=$CONTAINERS_UUID  /var/lib/containers  ext4  defaults,noatime,nodiratime,data=ordered  0  2

UUID=$ML_DATA_UUID  /mnt/ml-data  ext4  defaults,noatime,nodiratime,data=writeback,commit=30  0  2
UUID=$SCRATCH_UUID  /mnt/scratch  xfs  defaults,noatime,nodiratime,allocsize=16m,largeio  0  2

UUID=$DATA_UUID  /mnt/data  btrfs  defaults,noatime,compress=zstd:3,space_cache=v2,autodefrag,commit=120  0  2

tmpfs  /tmp  tmpfs  defaults,noatime,nosuid,nodev,size=2G  0  0
EOF

# Verify
cat /mnt/nvme_root/etc/fstab

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

## System Update (chroot)
# Fix resolv.conf
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
update-initramfs -c -k $(uname -r)
exit

# Copy kernel files
sudo cp /mnt/nvme_root/boot/vmlinuz-* /mnt/nvme_boot/vmlinuz
sudo cp /mnt/nvme_root/boot/initrd.img-* /mnt/nvme_boot/initrd.img


## Enable TRIM
sudo systemctl enable fstrim.timer
sudo systemctl start fstrim.timer


## Final Steps
# Sync
sync

# Unmount
sudo umount -lR /mnt/nvme_root
sudo umount /mnt/nvme_boot

# Poweroff
sudo poweroff

# Remove SD card and boot from NVMe!
