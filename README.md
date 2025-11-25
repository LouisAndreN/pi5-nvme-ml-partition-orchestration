# Setup of NVMe on Pi5 optimized for Smart Home

This project provides an optimized configuration and partitionning system on a 1 TB NVMe, booted on Raspberry Pi 5, optimized for orchestration of Edge AI devices, ML models and services for an advanced smart home.

The partitionning system is made as follows :

| Partition      | Size   | Fstype | Mount Point / Name         | Utility                                    |
|----------------|--------|--------|---------------------------|--------------------------------------------|
| nvme0n1p1      | 1 GiB  | vfat   | /boot/firmware            | Ubuntu Boot + space for kernels            |
| nvme0n1p2      | 100 GiB| ext4   | /                         | OS + libraries + AI frameworks + other services |
| nvme0n1p3      | 140 GiB| ext4   | /var                      | Logs + cache                               |
| nvme0n1p4      | 180 GiB| ext4   | /var/lib/containers       | Containers (Docker or Podman)             |
| nvme0n1p5      | 230 GiB| ext4   | /mnt/ml-data              | ML models + datasets                        |
| nvme0n1p6      | 60 GiB | xfs    | /mnt/scratch              | High performance buffer                     |
| nvme0n1p7      | 240 GiB| btrfs  | /mnt/data (space left)    | Personal data + backups + snapshots        |



/ 100 GB → OS (Ubuntu + kernels + initramfs + system packages = ~20GB) + Python/C++ dependencies + AI Frameworks (PyTorch, TensorFlow, Hailo SDK) + space for futures updates

/var 120 GB → large space for cache containers and logs (InfluxDB, Prometheus, Grafana）

/var/lib/containers 160 GB → space for volumes and images for Home Assistant, Frigate, Nextcloud, Portainer...

/mnt/ml-data 230 GB → ML models, checkpoints, datasets

/mnt/scratch 60 GB → C++, Rust, Hailo, AI tests

/mnt/data 220 GB (btrfs) → ZSTD compression + snapshots for media, backups, personal data

---


## How to install

Flash a SD card (max 64GB) with Ubuntu Server LTS with Raspberry Pi Imager. Plug the SD card and the NVMe on the Pi 5 and boot on the SD card.
Connect by SSH on the Pi.
Open the commands.sh file and execute all the commands one by one to setup the NVMe.
Once done, shutdown the Pi 5 and remove only the SD card.
Now the Pi should boot Ubuntu Server on the NVMe and you can connect to it by SSH.

---

## 日本語

詳細な手順は [Qiita記事]([https://qiita.com/YOUR_USERNAME/items/XXXXX](https://qiita.com/LouisAndreN/items/a5d286a591abda8e6553)) をご覧ください。

---




