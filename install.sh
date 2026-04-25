#!/usr/bin/env bash
# =============================================================================
#  Linux Rclone Local Mount — Universal Installer
#  Supports: Fedora, Ubuntu/Debian, Arch, openSUSE, Alpine, Void, Gentoo, NixOS
#  github.com/ShoumikBalaSomu/Linux-Rclone-Local-Mount
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

REPO="https://raw.githubusercontent.com/ShoumikBalaSomu/Linux-Rclone-Local-Mount/main"
INSTALL_DIR="${HOME}/.local/bin"
SCRIPT_NAME="rclone-mount"

echo -e "\n${BOLD}${CYAN}☁  Linux Rclone Local Mount — Universal Installer${RESET}\n"

# ── 0. Detect distro & package manager ─────────────────────────────────────
DISTRO_ID="unknown"
DISTRO_NAME="Unknown Linux"
PKG_MANAGER=""

if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_NAME="${PRETTY_NAME:-${NAME:-Unknown Linux}}"
fi

echo -e "  ${BOLD}Distro:${RESET}  ${DISTRO_NAME}"

# Detect package manager
if command -v apt-get &>/dev/null; then
    PKG_MANAGER="apt"
elif command -v dnf &>/dev/null; then
    PKG_MANAGER="dnf"
elif command -v yum &>/dev/null; then
    PKG_MANAGER="yum"
elif command -v pacman &>/dev/null; then
    PKG_MANAGER="pacman"
elif command -v zypper &>/dev/null; then
    PKG_MANAGER="zypper"
elif command -v apk &>/dev/null; then
    PKG_MANAGER="apk"
elif command -v xbps-install &>/dev/null; then
    PKG_MANAGER="xbps"
elif command -v emerge &>/dev/null; then
    PKG_MANAGER="emerge"
fi

echo -e "  ${BOLD}Package Manager:${RESET} ${PKG_MANAGER:-none detected}"
echo ""

# ── Helper: install packages via detected manager ──────────────────────────
pkg_install() {
    local pkgs=("$@")
    echo -e "${CYAN}Installing: ${pkgs[*]}...${RESET}"
    case "$PKG_MANAGER" in
        apt)     sudo apt-get update -qq && sudo apt-get install -y "${pkgs[@]}" ;;
        dnf)     sudo dnf install -y "${pkgs[@]}" ;;
        yum)     sudo yum install -y "${pkgs[@]}" ;;
        pacman)  sudo pacman -S --noconfirm "${pkgs[@]}" ;;
        zypper)  sudo zypper install -y "${pkgs[@]}" ;;
        apk)     sudo apk add "${pkgs[@]}" ;;
        xbps)    sudo xbps-install -y "${pkgs[@]}" ;;
        emerge)  sudo emerge --ask=n "${pkgs[@]}" ;;
        *)
            echo -e "${RED}No supported package manager found.${RESET}"
            echo -e "${DIM}Please install manually: ${pkgs[*]}${RESET}"
            return 1
            ;;
    esac
}

# ── 1. Install rclone if missing ───────────────────────────────────────────
if ! command -v rclone &>/dev/null; then
    echo -e "${YELLOW}rclone not found.${RESET}"
    case "$PKG_MANAGER" in
        apt)     pkg_install rclone ;;
        dnf|yum) pkg_install rclone ;;
        pacman)  pkg_install rclone ;;
        zypper)  pkg_install rclone ;;
        apk)     pkg_install rclone ;;
        xbps)    pkg_install rclone ;;
        emerge)  pkg_install net-misc/rclone ;;
        *)
            echo -e "${YELLOW}Attempting rclone.org universal installer...${RESET}"
            curl https://rclone.org/install.sh | sudo bash
            ;;
    esac
else
    echo -e "  ${GREEN}✓${RESET}  rclone $(rclone --version 2>/dev/null | head -1 | awk '{print $2}')"
fi

# ── 2. Install fuse3 if missing ────────────────────────────────────────────
if ! command -v fusermount3 &>/dev/null; then
    echo -e "${YELLOW}fusermount3 not found. Installing fuse3...${RESET}"
    case "$PKG_MANAGER" in
        apt)     pkg_install fuse3 ;;
        dnf|yum) pkg_install fuse fuse3 fuse3-libs ;;
        pacman)  pkg_install fuse3 ;;
        zypper)  pkg_install fuse3 ;;
        apk)     pkg_install fuse3 ;;
        xbps)    pkg_install fuse3 ;;
        emerge)  pkg_install sys-fs/fuse:3 ;;
        *)
            echo -e "${RED}Please install fuse3 manually for your distro.${RESET}"
            ;;
    esac
else
    echo -e "  ${GREEN}✓${RESET}  fusermount3"
fi

# ── 3. Enable user_allow_other in /etc/fuse.conf ──────────────────────────
if [[ -f /etc/fuse.conf ]] && ! grep -qE '^\s*user_allow_other' /etc/fuse.conf 2>/dev/null; then
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
    # Detect the user's shell config file
    local_shell=$(basename "${SHELL:-bash}")
    case "$local_shell" in
        zsh)  rc_file="${HOME}/.zshrc" ;;
        fish) rc_file="${HOME}/.config/fish/config.fish" ;;
        *)    rc_file="${HOME}/.bashrc" ;;
    esac
    if [[ "$local_shell" == "fish" ]]; then
        echo "set -gx PATH \$PATH ${INSTALL_DIR}" >> "$rc_file"
    else
        echo "export PATH=\"\$PATH:${INSTALL_DIR}\"" >> "$rc_file"
    fi
    echo -e "${YELLOW}Added ${INSTALL_DIR} to PATH in ${rc_file}${RESET}"
fi

# ── 6. Enable systemd lingering (if systemd is available) ────────────────
if command -v loginctl &>/dev/null; then
    loginctl enable-linger "$(whoami)" 2>/dev/null || true
fi

echo -e "\n${GREEN}${BOLD}✓ Installation complete!${RESET}"
echo -e "  ${BOLD}Distro:${RESET}   ${DISTRO_NAME}"
echo -e "  ${BOLD}Run with:${RESET} ${BOLD}${SCRIPT_NAME}${RESET}"
echo -e "  ${BOLD}Or:${RESET}       ${BOLD}${INSTALL_DIR}/${SCRIPT_NAME}${RESET}\n"
