# Automated Smart Home Full Deployer on {Pi + NVMe}

This project provides a deployment of a complete smart home system on a Raspberry Pi 5 with NVMe. It sets up an optimized partitioning system for Ubuntu Server LTS and domotic projects using ML and AI features.

The partitionning system is made as follows :

PARTITION         SIZE   FSTYPE  NAME             　　 UTILITY
nvme0n1
├─nvme0n1p1      1 GiB   vfat    /boot/firmware        Ubuntu Boot + space for kernels
├─nvme0n1p2    100 GiB   ext4    /                     OS + libraries + AI frameworks + space for other services
├─nvme0n1p3    140 GiB   ext4    /var                  logs + cache
├─nvme0n1p4    180 GiB   ext4    /var/lib/containers   Containers (Docker or Podman)
├─nvme0n1p5    230 GiB   ext4    /mnt/ml-data          ML models + datasets
├─nvme0n1p6     60 GiB   xfs     /mnt/scratch          High performance buffer
└─nvme0n1p7    240 GiB   btrfs   /mnt/data (残り)      Personal data + backups + snapshots


---


## How to install
1. Flash the SD card with the Ubuntu Server LTS OS.
2. Place the unzip folder in the root of the SD card.
3. Plug the SD card with the NVMe connected to the Pi 5 with an adapter.
4. Launch the Pi to boot on the SD card and deploy automatically the solution on the NVMe.
5. Connect to the Pi by SSH and execute the following command to see if the setup of the NVMe is done.
6. If done, shutdown the Pi with `sudo poweroff` and unplugged the SD card.
7. Now you're ready to boot on the NVMe and connect to the Pi.


---


## Future Features

- **Auto-deployment of services** :
    - **Firewall & security** — UFW, secure defaults, SSL support guidance
    - **Docker & Docker Compose** — containerized, reproducible deployment
    - **Squid Proxy** — caching and access control
    - **MinIO & Nextcloud** — personal cloud, file sync, and media storage  
    - **Home Assistant** — IoT automation hub for managing devices and scenes  
    - **Mosquitto MQTT** — central hub for ESP devices and sensors  
    - **ESPHome** — easy configuration for ESP-based devices  

---




