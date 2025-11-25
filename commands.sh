# Update and upgrade OS on SD card
sudo apt update && sudo apt full-upgrade -y

# Update EEPROM
sudo rpi-eeprom-update -a
sudo reboot

# Check if NVMe is detected
lspci | grep -i nvme

# Unmount existing partitions on the NVMe if existing
sudo umount /dev/nvme0n1p*

# Check if partitions are all unmounted -> nothing plotted
mount | grep nvme

# Clean and erase everything on the NVMe
sudo wipefs -a /dev/nvme0n1

# Check if NVMe was cleaned -> nothing plotted
sudo blkid /dev/nvme0n1

# Check the available space and size on the NVMe for partitionning
sudo fdisk -l /dev/nvme0n1 | grep "Disk /dev/nvme0n1"





GPTテーブルを作成する：

sudo parted /dev/nvme0n1

mklabel gpt

# パーティションを作成
mkpart primary fat32 1MiB 1025MiB     # 1. /boot/firmware
mkpart primary ext4 1025MiB 101GiB    # 2. /
mkpart primary ext4 101GiB 241GiB     # 3. /var
mkpart primary ext4 241GiB 421GiB     # 4. /var/lib/containers
mkpart primary ext4 421GiB 651GiB     # 5. /mnt/ml-data
mkpart primary xfs 651GiB 711GiB      # 6. /mnt/scratch
mkpart primary btrfs 711GiB 100%      # 7. /mnt/data


# パーティションブート用にマークする
set 1 boot on
set 1 esp on

# 作成されたパーティションを確認する
print

image.png

# parted を終了する
quit

アラインメントの問題を避けるため、先頭に1MiBを空けておきます。

lsblk /dev/nvme0n1を実行すると, これを取得します：

NAME        MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
nvme0n1     259:0    0 953.9G  0 disk
├─nvme0n1p1 259:8    0     1G  0 part
├─nvme0n1p2 259:9    0   100G  0 part
├─nvme0n1p3 259:10   0   140G  0 part
├─nvme0n1p4 259:11   0   180G  0 part
├─nvme0n1p5 259:12   0   230G  0 part
├─nvme0n1p6 259:13   0    60G  0 part
└─nvme0n1p7 259:14   0 242.9G  0 part

パーティションをフォーマットする

sudo mkfs.vfat -F32 -n system-boot /dev/nvme0n1p1
sudo mkfs.ext4 -L writable /dev/nvme0n1p2
sudo mkfs.ext4 /dev/nvme0n1p3
sudo mkfs.ext4 -L CONTAINERS /dev/nvme0n1p4
sudo mkfs.ext4 -L ML-DATA /dev/nvme0n1p5
sudo mkfs.xfs -f /dev/nvme0n1p6
sudo mkfs.btrfs -f -L DATA /dev/nvme0n1p7

今後識別が必要になる重要なパーティションにはラベルを付けます。
そのため、ブート用・OS用・ML-DATA用・DATA用 のパーティションのみにラベルを設定します。
ファイルシステム

lsblk -f /dev/nvme0n1を実行すると, UUIDを見える：

NAME        FSTYPE   LABEL          UUID
nvme0n1p1   vfat     system-boot    xxxx-xxxx
nvme0n1p2   ext4     writable       xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
nvme0n1p3   ext4                    xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
nvme0n1p4   ext4     CONTAINERS     xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
nvme0n1p5   ext4     ML-DATA        xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
nvme0n1p6   xfs                     xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
nvme0n1p7   btrfs    DATA           xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

DATA パーティションが btrfs でフォーマットされていることが表示されない可能性があります。sudo reboot を実行して再起動するだけで、NVMeからパーティションテーブルを再読み込みできます。
それでも表示されない場合は、sudo mkfs.btrfs -f -L DATA /dev/nvme0n1p7 を使って強制的にフォーマットできます。
UUIDを取得する

後で扱いやすくするため、パーティションのUUIDを変数に格納します：

BOOT_UUID=$(sudo blkid -s UUID -o value /dev/nvme0n1p1)
ROOT_UUID=$(sudo blkid -s UUID -o value /dev/nvme0n1p2)
VAR_UUID=$(sudo blkid -s UUID -o value /dev/nvme0n1p3)
CONTAINERS_UUID=$(sudo blkid -s UUID -o value /dev/nvme0n1p4)
ML_DATA_UUID=$(sudo blkid -s UUID -o value /dev/nvme0n1p5)
SCRATCH_UUID=$(sudo blkid -s UUID -o value /dev/nvme0n1p6)
DATA_UUID=$(sudo blkid -s UUID -t TYPE=btrfs /dev/nvme0n1p7 -o value)

BTRFS のパーティションは複数の UUID を持つため、blkid が混乱して空行を返すことがあります。そのため、sudo blkid -s UUID -t TYPE=btrfs /dev/nvme0n1p7 -o valueのコマンドを使用します。
ファイルにUUIDを保存

作業フォルダを作成する：

mkdir -p ~/nvme-setup

cat > ~/nvme-setup/uuids.txt <<EOF

>BOOT_UUID=$BOOT_UUID
>ROOT_UUID=$ROOT_UUID
>VAR_UUID=$VAR_UUID
>CONTAINERS_UUID=$CONTAINERS_UUID
>ML_DATA_UUID=$ML_DATA_UUID
>SCRATCH_UUID=$SCRATCH_UUID
>DATA_UUID=$DATA_UUID
>EOF

確認ために、表示されます：

cat ~/nvme-setup/uuids.txt

マウントポイントを作成する：

sudo mkdir -p /mnt/nvme_{boot,root,var,containers,ml,scratch,data}

全てのパーティションをマウントする：

sudo mount /dev/nvme0n1p1 /mnt/nvme_boot
sudo mount /dev/nvme0n1p2 /mnt/nvme_root
sudo mount /dev/nvme0n1p3 /mnt/nvme_var
sudo mount /dev/nvme0n1p4 /mnt/nvme_containers
sudo mount /dev/nvme0n1p5 /mnt/nvme_ml
sudo mount /dev/nvme0n1p6 /mnt/nvme_scratch
sudo mount /dev/nvme0n1p7 /mnt/nvme_data

マウントを確認する：

df -h | grep nvme

image.png
ブートパーティション設定（nvme0n1p1）

SD カードのブートパーティションを読み取り専用でマウントする：

sudo mount -o remount,ro /boot/firmware

ブートパーティションをコピーする：

sudo rsync -axHAWX --info=progress2 /boot/firmware/ /mnt/nvme_boot/

SDカードのブートパーティションを読み書き可能でマウントする：

sudo mount -o remount,rw /boot/firmware

コピーを確認する：

ls -la /mnt/nvme_boot/
du -sh /mnt/nvme_boot/

cmdline.txt, config.txt, initrd.img, vmlinuzなどのファイルリストを確認する必要があります。

cmdline.txt が依存しているかどうかを確認する：

cat /mnt/nvme_boot/cmdline.txt

console=serial0,115200 multipath=off dwc_otg.lpm_enable=0 console=tty1 root=LABEL=writable rootfstype=ext4 rootwait fixrtc cfg80211.ieee80211_regdom=JP

cmdline.txt に root=LABEL=writable が設定されている必要があります。
ブートに問題を避けるために、root=UUID=<UUID_of_/boot/firmware>でroot=LABEL=writableを変更できます。
ルートパーティション設定（nvme0n1p2）

SDカードからOSをコピーします：

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

mkfs.ext4でlost+foundが自動的に作成されましたので、各ext4のパーティションが自分のlost+foundを持ちます。SDのをコピーするのが無駄で、
SD のものをコピーしても意味がなく、衝突を引き起こす可能性があります。

コピーを確認します：

ls -la /mnt/nvme_root/
sudo du -sh /mnt/nvme_root/

image.png

image.png

必須のバイナリが存在するか確認する：

ls -la /mnt/nvme_root/usr/bin/bash
ls -la /mnt/nvme_root/usr/sbin/init

image.png

不足しているディレクトリを作成する：

sudo mkdir -p /mnt/nvme_root/{boot/firmware,proc,sys,dev,run,tmp,mnt,media}
sudo mkdir -p /mnt/nvme_root/mnt/{ml-data,scratch,data}
sudo mkdir -p /mnt/nvme_root/var/lib/containers

Docker 以外、/var をコピーする：

sudo rsync -axHAWX --info=progress2 \
  --exclude=/var/lib/containers \
  --exclude=/var/tmp \
  --exclude=/var/cache/apt/archives/*.deb \
  --exclude=/var/lost+found \
  /var/ /mnt/nvme_var/

正しくコピーされたかどうかをかくにんします：

ls -la /mnt/nvme_var/
du -sh /mnt/nvme_var/

image.png

image.png

Copier aussi /var/lib/containers vers sa partition

sudo rsync -axHAWX --info=progress2 \
  /var/lib/containers/ /mnt/nvme_containers/

/mnt/nvme_boot/cmdline.txt の設定

sudo nano /mnt/nvme_boot/cmdline.txt

/mnt/nvme_boot/cmdline.txt

console=serial0,115200 multipath=off dwc_otg.lpm_enable=0 console=tty1 root=LABEL=writable rootfstype=ext4 rootwait fixrtc cfg80211.ieee80211_regdom=JP

すべて1行で、改行しないこと。

確認（1行になっていること）：

cat /mnt/nvme_boot/cmdline.txt
wc -l /mnt/nvme_boot/cmdline.txt  # 1を表示する

/etc/fstab の設定

UUIDを再読み込みする：

source ~/nvme-setup/uuids.txt

sudo tee /mnt/nvme_root/etc/fstab > /dev/null <<EOF

>UUID=$BOOT_UUID  /boot/firmware  vfat  defaults  0  2
>UUID=$ROOT_UUID  /  ext4  defaults,noatime  0  1

# パーティションシステム
>UUID=$VAR_UUID  /var  ext4  defaults,noatime,barrier=1  0  2
>UUID=$CONTAINERS_UUID  /var/lib/containers  ext4  defaults,noatime,nodiratime,data=ordered  0  2

# ML パーティション
>UUID=$ML_DATA_UUID  /mnt/ml-data  ext4  defaults,noatime,nodiratime,data=writeback,commit=30  0  2
>UUID=$SCRATCH_UUID  /mnt/scratch  xfs  defaults,noatime,nodiratime,allocsize=16m,largeio  0  2

# DATA パーティション
>UUID=$DATA_UUID  /mnt/data  btrfs  defaults,noatime,compress=zstd:3,space_cache=v2,autodefrag,commit=120  0  2
>tmpfs  /tmp  tmpfs  defaults,noatime,nosuid,nodev,size=2G  0  0
>EOF

tmpfs /tmp tmpfs defaults,noatime,nosuid,nodev,size=512M 0 0 :
tmpfs に /tmp をマウントする（一部の操作を高速化することとNVMeの摩耗を減らすために）
tmpfs /var/log tmpfs defaults,noatime,nosuid,nodev,size=200M 0 0 :
tmpfs に /var/log をマウントする

fstabを確認します：

cat /mnt/nvme_root/etc/fstab

EEPROM を編集します：

sudo rpi-eeprom-config --edit

以下のことを書き込みます：
rpi-eeprom-config

[all]
BOOT_UART=0
POWER_OFF_ON_HALT=0
BOOT_ORDER=0xf641
PCIE_PROBE=1

BOOT_UART=1 : シリアルポートにファームウェアのメッセージを表示するために、ブートをする時に、UART出力を有効にします。デバッグ時には便利ですが、デバッグが完了したら 0 に設定できます。

POWER_OFF_ON_HALT=0 : Linuxが停止のコマンドを実行する時のPiの行動 -> Piはシャットダウンしますが、電源は完全には切れません。

これは電源とコントローラの負荷を軽減し、自動再起動を可能にするためです。
BOOT_ORDER=0xf641 : まずSDカード、次USB、最後NVMeをテストします。この順番で NVMe に問題が発生した場合は、SD を挿すだけで SD から直接ブートできるようになります。
SD に問題がある場合は、USB からブートするようにできます。

PCIE_PROBE=1 : SunFounder Dual NVMe Raft のアダプターが非HATということなので、この行を追加しなければなりません。

sudo rpi-eeprom-update -a

コンフィグを変更します：

sudo nano /mnt/nvme_boot/config.txt

/mnt/nvme_boot/config.txt

[all]

# PCIe Gen3 for NVMe (max speed)
dtparam=pciex1_gen=3

# 64-bit kernel
arm_64bit=1

# Kernel and initramfs
kernel=vmlinuz
cmdline=cmdline.txt
initramfs initrd.img followkernel


# Enable the audio output, I2C and SPI interfaces on the GPIO header. As these
# parameters related to the base device-tree they must appear *before* any
# other dtoverlay= specification
dtparam=audio=on
dtparam=i2c_arm=on
dtparam=spi=on

# Comment out the following line if the edges of the desktop appear outside
# the edges of your display
disable_overscan=1

# If you have issues with audio, you may try uncommenting the following line
# which forces the HDMI output into HDMI mode instead of DVI (which doesn't
# support audio output)
#hdmi_drive=2

# Enable the KMS ("full" KMS) graphics overlay, leaving GPU memory as the
# default (the kernel is in control of graphics memory with full KMS)
dtoverlay=vc4-kms-v3d
disable_fw_kms_setup=1

# Enable the serial pins
enable_uart=1

# Autoload overlays for any recognized cameras or displays that are attached
# to the CSI/DSI ports. Please note this is for libcamera support, *not* for
# the legacy camera stack
camera_auto_detect=1
display_auto_detect=1

# Config settings specific to arm64
dtoverlay=dwc2

[pi4]
max_framebuffers=2
arm_boost=1

[pi3+]
# Use a smaller contiguous memory area, specifically on the 3A+ to avoid an
# OOM oops on boot. The 3B+ is also affected by this section, but it shouldn't
# cause any issues on that board
dtoverlay=vc4-kms-v3d,cma-128

[pi02]
# The Zero 2W is another 512MB board which is occasionally affected by the same
# OOM oops on boot.
dtoverlay=vc4-kms-v3d,cma-128

[cm4]
# Enable the USB2 outputs on the IO board (assuming your CM4 is plugged into
# such a board)
dtoverlay=dwc2,dr_mode=host

[pi5]
dtparam=pciex1


[all]

公式 HAT アダプターは自動設定用の EEPROM を備えていますが、非 HAT アダプターの場合は手動でのコンフィグが必要です。

/mnt/nvme_boot/config.txtのためも、同じことを行う：

sudo apt update
sudo apt full-upgrade -y
sudo reboot

resolv.confを確認

ls -la /mnt/nvme_root/etc

resolv.confはsystemd-resolvedへのシンボリックリンクです。

lrwxrwxrwx   1 root root         39 Aug  6 01:59 resolv.conf -> ../run/systemd/resolve/stub-resolv.conf

# シンボリックリンクを解除して、resolv.confをコピー
sudo rm /mnt/nvme_root/etc/resolv.conf
sudo cp /etc/resolv.conf /mnt/nvme_root/etc/resolv.conf

NVMeシステム環境内でchrootを行います：

sudo mount -t proc /proc /mnt/nvme_root/proc
sudo mount -t sysfs /sys /mnt/nvme_root/sys
sudo mount --rbind /dev /mnt/nvme_root/dev

sudo mount -t devpts devpts /mnt/nvme_root/dev/pts

sudo mount --bind /run /mnt/nvme_root/run
sudo mount -t tmpfs tmpfs /mnt/nvme_root/tmp

chroot環境に入る：

sudo chroot /mnt/nvme_root /bin/bash

今、NVMe環境内にいます。
すべてアップデート：

apt update
apt full-upgrade -y

改良したカーネルをインストール：

apt install linux-raspi linux-image-raspi linux-headers-raspi -y

ファームウェアをアップデート：

apt install linux-firmware-raspi -y

/mnt/nvme_rootで initramfs を再生成することで、initrd.img-...ファイルが作成されます：

update-initramfs -c -k $(uname -r)

chrootから退出する：

exit

次に、先ほど生成した initramfs のファイルをコピーし、直接 /mnt/nvme_boot に vmlinuz と initrd.img として名前を付けます。

sudo cp /mnt/nvme_root/boot/vmlinuz-6.8.0-1040-raspi /mnt/nvme_boot/vmlinuz
sudo cp /mnt/nvme_root/boot/initrd.img-6.8.0-1040-raspi /mnt/nvme_boot/initrd.img

最適化

NVMeの性能と寿命を最適化するために、TRIMを有効にします：

sudo systemctl enable fstrim.timer
sudo systemctl start fstrim.timer

ブートのテスト

正しくアンマウントする：

sync
sudo umount -lR /mnt/nvme_root
sudo umount -lR /mnt/nvme_boot

Piをシャットダウンする：

sudo poweroff

