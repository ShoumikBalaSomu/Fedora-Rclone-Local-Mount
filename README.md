# ☁️ Fedora Rclone Local Mount Manager

<div align="center">
  <img src="https://img.shields.io/badge/Version-3.0.0-blueviolet?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Fedora-Ready-blue?style=for-the-badge&logo=fedora" />
  <img src="https://img.shields.io/badge/Rclone-Sync%20Optimised-orange?style=for-the-badge&logo=rclone" />
  <img src="https://img.shields.io/badge/Status-Production-brightgreen?style=for-the-badge" />
  <img src="https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge" />
</div>

---

## 📖 Overview

A **professional-grade**, all-in-one interactive Bash script to **mount, manage, and auto-boot** any cloud storage provider on Fedora Linux — powered by **rclone**, **FUSE**, and **systemd**.

Unlike a basic `rclone mount`, this project provides **sync-optimised VFS settings** that ensure local file changes are **flushed to the cloud within seconds**, while remote changes are detected promptly. Supports Google Drive, OneDrive, Dropbox, S3, SFTP, and 70+ more.

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🔄 **Auto-Mount on Boot** | Systemd user service integration for seamless background mounting |
| ⚡ **Real-Time Sync** | VFS write-back of **5 seconds** — local changes upload to cloud almost instantly |
| 📡 **Remote Change Detection** | Poll interval of **15 seconds** ensures you see cloud-side changes quickly |
| 🛡️ **Reliability** | Automatic restarts, stale mount cleanup, and error handling |
| 💾 **Smart Caching** | Full VFS cache with 24h expiry for offline resilience + fast access |
| 🗂 **Named Profiles** | Save each mount configuration as a reusable profile |
| 🛠️ **Dependency Checker** | Auto-detects and installs rclone, fuse3, systemd via dnf |
| 🖥️ **CLI & Scriptable** | Non-interactive flags: `--list`, `--mount-all`, `--unmount-all`, `--status` |
| 📊 **Live Status Dashboard** | See all mounts, VFS cache modes, disk usage, systemd unit health |

## 🚀 Quick Install

**One-line installer:**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ShoumikBalaSomu/Fedora-Rclone-Local-Mount/main/install.sh)
```

**Or clone manually:**
```bash
git clone https://github.com/ShoumikBalaSomu/Fedora-Rclone-Local-Mount.git
cd Fedora-Rclone-Local-Mount
chmod +x rclone-mount.sh
./rclone-mount.sh
```

## 🔧 How It Works

### VFS Cache Settings (v3.0.0 — Sync-Optimised)

The critical settings that control **local ↔ cloud synchronisation**:

| Flag | Value | Effect |
|------|-------|--------|
| `--vfs-cache-mode` | `full` | Full read/write caching for maximum app compatibility |
| `--vfs-write-back` | `5s` | **Local changes are uploaded to cloud within 5 seconds** |
| `--poll-interval` | `15s` | Checks remote for changes every 15 seconds |
| `--dir-cache-time` | `5m` | Directory listings refresh every 5 minutes |
| `--vfs-cache-max-age` | `24h` | Cached files expire after 24 hours |
| `--vfs-cache-poll-interval` | `1m` | Cache validity re-checked every minute |
| `--vfs-read-ahead` | `128M` | 128 MB read-ahead buffer for streaming performance |
| `--attr-timeout` | `1s` | File attributes refresh every second |

### Systemd Service

The generated systemd user service (`~/.config/systemd/user/rclone-*.service`):

```ini
[Unit]
Description=Rclone Mount — <name> (<remote>)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStartPre=/bin/mkdir -p <mountpoint>
ExecStartPre=-/bin/fusermount3 -uz <mountpoint>
ExecStart=/usr/bin/rclone mount <remote> <mountpoint> --vfs-cache-mode full --vfs-write-back 5s --poll-interval 15s ...
ExecStop=/bin/fusermount3 -u <mountpoint>
Restart=on-failure
RestartSec=10s
Environment=RCLONE_LOG_LEVEL=INFO

[Install]
WantedBy=default.target
```

Key design decisions:
- **`Type=simple`** — avoids systemd timeout loops (rclone doesn't send `sd_notify`)
- **`ExecStartPre=-/bin/fusermount3 -uz`** — cleans stale FUSE mounts before starting (the `-` prefix ignores errors if not mounted)
- **`Restart=on-failure`** — automatically recovers from crashes or network drops

## 📋 CLI Usage

```bash
rclone-mount --list           # List all mounted drives
rclone-mount --mount-all      # Mount all saved profiles
rclone-mount --unmount-all    # Unmount all rclone drives
rclone-mount --status         # Show system status & disk usage
rclone-mount --check          # Check dependencies only
rclone-mount --help           # Show help
```

## 📁 File Structure

```
Fedora-Rclone-Local-Mount/
├── rclone-mount.sh          # Main interactive TUI script
├── install.sh               # One-line installer
├── config/
│   └── mount.conf.example   # Example profile configuration
├── index.html               # GitHub Pages landing page
├── .editorconfig             # Editor configuration
├── LICENSE                   # MIT License
└── README.md                 # This file
```

## ☁️ Supported Cloud Providers

Any storage backend supported by [rclone](https://rclone.org/overview/) works out of the box:

> Google Drive • OneDrive • Dropbox • Amazon S3 • Backblaze B2 • SFTP • WebDAV • Box • pCloud • Mega • Wasabi • DigitalOcean Spaces • and 70+ more

## 🔄 Changelog

### v3.0.0 — Sync-Optimised (2026-04-25)
- **FIXED**: Local files now sync to cloud properly
  - Changed `--vfs-write-back` from `9999h` → `5s` (was caching writes for ~416 days!)
  - Changed `--poll-interval` from `0` → `15s` (was completely disabling remote change detection)
  - Changed `--dir-cache-time` from `9999h` → `5m`
  - Changed `--vfs-cache-max-age` from `9999h` → `24h`
- **ADDED**: `--vfs-cache-poll-interval 1m` for cache freshness checks
- **ADDED**: `ExecStartPre=-/bin/fusermount3 -uz` to clean stale mounts before start
- **ADDED**: `Environment=RCLONE_LOG_LEVEL=INFO` in systemd unit
- Bumped version to 3.0.0

### v2.0.0
- Changed `Type=notify` → `Type=simple` (fixed systemd timeout loop)
- Initial interactive TUI with profile management

### v1.0.0
- Initial release

## 📜 License

Licensed under the [MIT License](LICENSE). Copyright © 2026 Shoumik Bala Somu.

---

<div align="center">
  <p><strong>Bridging the gap between Cloud and Local storage.</strong> ☁️💻</p>
  <p><em>Made with ❤️ by <a href="https://github.com/ShoumikBalaSomu">ShoumikBalaSomu</a></em></p>
</div>
