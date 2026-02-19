# NVMe Encrypted LVM Setup for Edge IoT/ML on Raspberry Pi 5

This project provides an optimized configuration and partitionning system on a 1 TB NVMe, booted on Raspberry Pi 5, optimized for orchestration of Edge AI devices, ML models and services for an advanced smart home.
It uses Ubuntu Server LTS 23.03.4 and tested on Micron 2200 NVMe – read: BW=~850–950 MB/s et write: BW=~750–900 MB/s

The script '/opt/verify-boot.sh' is generated automatically during the installation and launched manually after the first boot on NVMe to validate all mounts LUKS, LVM, FS tuning, TRIM, etc.

The partitionning system is made as follows :

| Partition / LV          | Size     | FSType | Mount Point / Name                  | Utility / Description                                                                |
|-------------------------|----------|--------|-------------------------------------|--------------------------------------------------------------------------------------|
| nvme0n1p1               | 1 GB     | vfat   | /boot/firmware                      | Ubuntu boot + multiple kernels                                                       |
| nvme0n1p2               | 100 GB   | ext4   | /                                   | OS + libs + AI frameworks (Hailo SDK, PyTorch) + AWS CLI + Terraform + Azure CLI     |
| nvme0n1p3               | 16 GB    | swap   | swap                                | Dedicated Swap ML/Hailo (2× RAM, except LVM for performances)                        |
| nvme0n1p4               | 5 GB     | ext4   | /recovery                           | Emergency rescue : Backup LUKS header + scripts repair + mini-tools (cryptsetup, lvm2, btrfs-progs, ddrescue) |
| nvme0n1p5               | 838 GB   | LUKS   | cryptdata (encrypted)               | LUKS encryption                                                                      |
| ├─ vg-main              | 838 GB   | LVM    | Volume Group                        | Group LVM Volume on cryptdata                                                        |
| ├─ lv-var               | 20 GB    | ext4   | /var                                | System cache (APT, systemd, tmp)                                                     |
| ├─ lv-logs              | 30 GB    | ext4   | /var/log                            | Logs ESP32 + HA + Influx + cloud ops (7 days rotation, persistant journald)          |
| ├─ lv-influxdb          | 120 GB   | xfs    | /var/lib/influxdb                   | IoT Timeseries (tier 1-3 : 48h-30d ; tier 4 >30j S3 export daily through cron/MinIO gateway) |
| ├─ lv-containers        | 80 GB    | xfs    | /var/lib/containers                 | Docker/Podman (HA, MQTT, Grafana, Nextcloud, MinIO, Prometheus – except DB)          |
| ├─ lv-grafana           | 10 GB    | ext4   | /var/lib/grafana                    | Dashboards + provisioning + plugins + SQLite                                         |
| ├─ lv-ml-models         | 60 GB    | xfs    | /mnt/ml-models                      | production/ (active models Hailo)<br>staging/ (A/B testing)<br>archived/ (rollback)<br>datasets/ (training data local edge) |
| ├─ lv-ml-cache          | 40 GB    | xfs    | /mnt/ml-cache                       | staging/ (validation SageMaker-like)<br>training_data/ (export cloud)<br>logs/ (TensorBoard, ML metrics) |
| ├─ lv-cloud-sync        | 80 GB    | xfs    | /mnt/cloud-sync                     | pending/ (Influx export in progress)<br>uploading/ (upload S3/Azure en cours)<br>uploaded/ (success, retention 7d)<br>failed/ (retry + Prometheus alerts) |
| ├─ lv-scratch           | 60 GB    | xfs    | /mnt/scratch                        | Buffer preprocessing (nowcasting camera images, device electrical signatures)        |
| ├─ lv-data              | 338 GB   | btrfs  | /mnt/data                           | @iot-hot/ (active data 7-30d, quota 100 GiB)<br>@iot-archives (long term multi-year, compression zstd:3 max)<br>@backups (exported snapshots LVM, send/receive to cloud)<br>@personal (docs, source code) |


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




