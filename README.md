# Setup of NVMe on Pi5 optimized for Smart Home IoT

This project provides an optimized configuration and partitionning system on a 1 TB NVMe, booted on Raspberry Pi 5, optimized for orchestration of Edge AI devices, ML models and services for an advanced smart home.
It uses Ubuntu Server LTS 23.03.4.

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

nvme0n1 (1 TB Samsung 990 PRO)
├─nvme0n1p1  │    1 GB  │  vfat  │   /boot/firmware  │  Ubuntu boot + kernels multiples
├─nvme0n1p2  │  100 GB  │  ext4  │   /               │  OS + libs + AI frameworks (Hailo SDK, PyTorch) + AWS CLI + Terraform + Azure CLI
├─nvme0n1p3  │   16 GB  │  swap  │   swap            │  Swap dédié ML/Hailo (2× RAM, hors LVM pour perf)
├─nvme0n1p4  │    5 GB  │  ext4  │   /recovery       │  Emergency rescue : Backup LUKS header + scripts repair + mini-tools (cryptsetup, lvm2, btrfs-progs, ddrescue)
└─nvme0n1p5  │  838 GB  │  LUKS  │   cryptdata (encrypted)
   └─vg-main     838 GB   LVM     Volume Group
     ├─lv-var       20 GB   ext4    /var  │  Cache système (APT, systemd, tmp)
     ├─lv-logs      30 GB   ext4    /var/log  │  Logs ESP32 + HA + Influx + cloud ops (rotation 7j, journald persistante)
     ├─lv-influxdb 120 GB   xfs     /var/lib/influxdb  │  Timeseries IoT (tier 1-3 : 48h-30j ; tier 4 >30j export S3 quotidien via cron/MinIO gateway)
     ├─lv-containers 80 GB   xfs     /var/lib/containers  │  Docker/Podman (HA, MQTT, Grafana, Nextcloud, MinIO, Prometheus – hors DB)
     ├─lv-grafana   10 GB   ext4    /var/lib/grafana    │  Dashboards + provisioning + plugins + SQLite
     ├─lv-ml-models  60 GB   xfs     /mnt/ml-models  │  ├─ production/ (modèles actifs Hailo)
                                                     │  ├─ staging/ (A/B testing)
                                                     │  ├─ archived/ (rollback)
                                                     │  └─ datasets/ (training data local edge)
     ├─lv-ml-cache   40 GB   xfs     /mnt/ml-cache   │  ├─ staging/ (validation SageMaker-like)
                                                     │  ├─ training_data/ (export cloud)
                                                     │  └─ logs/ (TensorBoard, métriques ML)
     ├─lv-cloud-sync 80 GB   xfs     /mnt/cloud-sync  │  ├─ pending/ (Influx export en cours)
                                                       │  ├─ uploading/ (upload S3/Azure en cours)
                                                       │  ├─ uploaded/ (succès, rétention 7j)
                                                       │  └─ failed/ (retry + alert Prometheus)
     ├─lv-scratch    60 GB   xfs     /mnt/scratch    │  Buffer preprocessing (images caméra nowcasting, signatures électriques)
     └─lv-data      338 GB   btrfs   /mnt/data   │  ├─ @iot-hot/     (données actives 7-30j, quota 100 GiB)
                                                    ├─ @iot-archives (long terme multi-années, compression zstd:3 max)
                                                    ├─ @backups      (snapshots LVM exportés, send/receive vers cloud)
                                                    └─ @personal     (portfolio Git, docs, code source)



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
Open the setup_commands.sh file and execute all the commands one by one to setup the NVMe.
Once done, shutdown the Pi 5 and remove only the SD card.
Now the Pi should boot Ubuntu Server on the NVMe and you can connect to it by SSH.

---

## 日本語

詳細な手順は [Qiita記事](https://qiita.com/LouisAndreN/items/a5d286a591abda8e6553) をご覧ください。

---




