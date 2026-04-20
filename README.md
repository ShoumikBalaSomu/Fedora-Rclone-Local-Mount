# ☁️ Fedora Rclone Local Mount Automation

<div align="center">
  <img src="https://img.shields.io/badge/Fedora-Ready-blue?style=for-the-badge&logo=fedora" />
  <img src="https://img.shields.io/badge/Rclone-Automation-orange?style=for-the-badge&logo=rclone" />
  <img src="https://img.shields.io/badge/Status-Optimized-brightgreen?style=for-the-badge" />
  <img src="https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge" />
</div>

---

## 📖 Overview
Automate the process of mounting cloud storage (Google Drive, OneDrive, etc.) as local drives on Fedora using **Rclone**. This project provides a robust systemd service configuration to ensure your cloud mounts are persistent across reboots and handle network interruptions gracefully.

## ✨ Features
- 🔄 **Auto-Mount on Boot**: Systemd integration for seamless background mounting.
- ⚡ **High Performance**: Optimized VFS cache settings for zero-disk streaming.
- 🛡️ **Reliability**: Automatic restarts and error handling.
- 🛠️ **Easy Config**: Simple shell script to setup your remote and local paths.

## 🚀 Getting Started

1. **Clone the repository**:
   ```bash
   git clone https://github.com/shoumikbalasomu/Fedora-Rclone-Local-Mount.git
   cd Fedora-Rclone-Local-Mount
   ```

2. **Configure Rclone**:
   Ensure you have configured your rclone remote using `rclone config`.

3. **Install the service**:
   Edit the `setup_mount.sh` with your remote name and mount path, then run:
   ```bash
   chmod +x setup_mount.sh
   sudo ./setup_mount.sh
   ```

## 🛠️ Systemd Integration
The project includes a pre-configured `.service` file that you can customize for your specific cloud provider and local mount point.

## 📜 License
Licensed under the [MIT License](LICENSE). Copyright © 2026 Shoumik Bala Somu.

---

<div align="center">
  <p>Bridging the gap between Cloud and Local storage. ☁️💻</p>
</div>
