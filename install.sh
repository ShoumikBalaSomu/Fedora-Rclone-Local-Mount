#!/usr/bin/env bash
# =============================================================================
#  Fedora Rclone Local Mount — Installer
#  github.com/ShoumikBalaSomu/Fedora-Rclone-Local-Mount
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

REPO="https://raw.githubusercontent.com/ShoumikBalaSomu/Fedora-Rclone-Local-Mount/main"
INSTALL_DIR="${HOME}/.local/bin"
SCRIPT_NAME="rclone-mount"

echo -e "\n${BOLD}${CYAN}Fedora Rclone Local Mount — Installer${RESET}\n"

# ── 1. Install rclone if missing ───────────────────────────────────────────
if ! command -v rclone &>/dev/null; then
    echo -e "${YELLOW}rclone not found. Installing via dnf...${RESET}"
    sudo dnf install -y rclone
fi

# ── 2. Install fuse3 if missing ────────────────────────────────────────────
if ! rpm -q fuse3 &>/dev/null; then
    echo -e "${YELLOW}fuse3 not found. Installing...${RESET}"
    sudo dnf install -y fuse fuse3 fuse3-libs
fi

# ── 3. Enable user_allow_other in /etc/fuse.conf ──────────────────────────
if ! grep -q "^user_allow_other" /etc/fuse.conf 2>/dev/null; then
    echo -e "${YELLOW}Enabling user_allow_other in /etc/fuse.conf...${RESET}"
    sudo sh -c 'echo "user_allow_other" >> /etc/fuse.conf'
fi

# ── 4. Download main script ────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR"
echo -e "${CYAN}Downloading rclone-mount.sh...${RESET}"
curl -fsSL "${REPO}/rclone-mount.sh" -o "${INSTALL_DIR}/${SCRIPT_NAME}"
chmod +x "${INSTALL_DIR}/${SCRIPT_NAME}"

# ── 5. Ensure ~/.local/bin is in PATH ─────────────────────────────────────
if [[ ":$PATH:" != *":${INSTALL_DIR}:"* ]]; then
    echo "export PATH=\"\$PATH:${INSTALL_DIR}\"" >> "${HOME}/.bashrc"
    echo -e "${YELLOW}Added ${INSTALL_DIR} to PATH in ~/.bashrc${RESET}"
fi

# ── 6. Enable systemd lingering ───────────────────────────────────────────
loginctl enable-linger "$(whoami)" 2>/dev/null || true

echo -e "\n${GREEN}${BOLD}✓ Installation complete!${RESET}"
echo -e "  Run with: ${BOLD}${SCRIPT_NAME}${RESET}"
echo -e "  Or:       ${BOLD}${INSTALL_DIR}/${SCRIPT_NAME}${RESET}\n"
