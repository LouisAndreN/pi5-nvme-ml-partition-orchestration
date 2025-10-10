# Smart Home Pi Full Deployer

**Automated full-stack Smart Home installer for Raspberry Pi (NVMe boot)**

This project provides a ready-to-use, automated deployment of a complete smart home system on a Raspberry Pi 5 with NVMe. It sets up all essential services so you can have an operational smart home. It includes a local storage server Nextcloud and a local proxy Squid for automated and securized updates of services.

---

## Key Features

- **Firewall & security** — UFW, secure defaults, SSL support guidance
- **Docker & Docker Compose** — containerized, reproducible deployment
- **Squid Proxy** — caching and access control
- **Nextcloud** — personal cloud, file sync, and media storage  
- **Home Assistant** — IoT automation hub for managing devices and scenes  
- **Mosquitto MQTT broker** — central hub for ESP devices and sensors  
- **ESPHome** — easy configuration for ESP-based devices  


---

## How to install

1. **Boot your Raspberry Pi** from SD card with NVMe plugged.  
2. **Run the installation script**: it detects the NVMe, formats it if necessary, and copy the OS from SD card, Docker, and all services.  
3. **Configuration is automatic**, including firewall, Docker containers, and essential services.  

> Optional: future versions may support other services and **network-based detection and automated deployment** with other devices.



