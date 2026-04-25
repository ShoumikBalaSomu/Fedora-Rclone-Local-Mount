#!/usr/bin/env bash
# =============================================================================
#  ██████╗  ██████╗██╗      ██████╗ ███╗   ██╗███████╗
#  ██╔══██╗██╔════╝██║     ██╔═══██╗████╗  ██║██╔════╝
#  ██████╔╝██║     ██║     ██║   ██║██╔██╗ ██║█████╗
#  ██╔══██╗██║     ██║     ██║   ██║██║╚██╗██║██╔══╝
#  ██║  ██║╚██████╗███████╗╚██████╔╝██║ ╚████║███████╗
#  ╚═╝  ╚═╝ ╚═════╝╚══════╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝
#
#  Linux Rclone Local Mount Manager
#  Author  : ShoumikBalaSomu
#  GitHub  : https://github.com/ShoumikBalaSomu/Fedora-Rclone-Local-Mount
#  License : MIT
#  Version : 4.0.0
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
#  GLOBAL CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────
readonly SCRIPT_VERSION="4.0.0"
readonly SCRIPT_NAME="Linux Rclone Local Mount Manager"
readonly CONFIG_DIR="${HOME}/.config/rclone-mounter"
readonly CONFIG_FILE="${CONFIG_DIR}/mounts.conf"
readonly LOG_FILE="${CONFIG_DIR}/rclone-mounter.log"
readonly SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
readonly DEFAULT_MOUNT_BASE="${HOME}/CloudDrives"
readonly RCLONE_BIN=$(command -v rclone 2>/dev/null || true)

# ─────────────────────────────────────────────────────────────────────────────
#  DISTRO & PACKAGE MANAGER DETECTION
# ─────────────────────────────────────────────────────────────────────────────
DISTRO_ID="unknown"
DISTRO_NAME="Unknown Linux"
PKG_MANAGER=""

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        DISTRO_ID="${ID:-unknown}"
        DISTRO_NAME="${PRETTY_NAME:-${NAME:-Unknown Linux}}"
    elif [[ -f /etc/lsb-release ]]; then
        # shellcheck source=/dev/null
        source /etc/lsb-release
        DISTRO_ID="${DISTRIB_ID,,}"
        DISTRO_NAME="${DISTRIB_DESCRIPTION:-Unknown Linux}"
    elif command -v lsb_release &>/dev/null; then
        DISTRO_ID=$(lsb_release -si 2>/dev/null | tr '[:upper:]' '[:lower:]')
        DISTRO_NAME=$(lsb_release -sd 2>/dev/null)
    fi
    log_debug "Detected distro: ${DISTRO_ID} (${DISTRO_NAME})"
}

detect_pkg_manager() {
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
    elif command -v nix-env &>/dev/null; then
        PKG_MANAGER="nix"
    else
        PKG_MANAGER=""
    fi
    log_debug "Detected package manager: ${PKG_MANAGER:-none}"
}

install_packages() {
    # install_packages <pkg1> <pkg2> ...
    local pkgs=("$@")
    log_info "Installing: ${pkgs[*]} via ${PKG_MANAGER}..."
    case "$PKG_MANAGER" in
        apt)
            sudo apt-get update -qq >> "$LOG_FILE" 2>&1 || true
            sudo apt-get install -y "${pkgs[@]}" >> "$LOG_FILE" 2>&1
            ;;
        dnf)
            sudo dnf install -y "${pkgs[@]}" >> "$LOG_FILE" 2>&1
            ;;
        yum)
            sudo yum install -y "${pkgs[@]}" >> "$LOG_FILE" 2>&1
            ;;
        pacman)
            sudo pacman -S --noconfirm "${pkgs[@]}" >> "$LOG_FILE" 2>&1
            ;;
        zypper)
            sudo zypper install -y "${pkgs[@]}" >> "$LOG_FILE" 2>&1
            ;;
        apk)
            sudo apk add "${pkgs[@]}" >> "$LOG_FILE" 2>&1
            ;;
        xbps)
            sudo xbps-install -y "${pkgs[@]}" >> "$LOG_FILE" 2>&1
            ;;
        emerge)
            sudo emerge --ask=n "${pkgs[@]}" >> "$LOG_FILE" 2>&1
            ;;
        nix)
            nix-env -iA "${pkgs[@]}" >> "$LOG_FILE" 2>&1
            ;;
        *)
            log_error "No supported package manager found. Please install manually: ${pkgs[*]}"
            return 1
            ;;
    esac
}

get_fuse_packages() {
    # Returns the correct fuse package names for the current distro/pkg manager
    case "$PKG_MANAGER" in
        apt)     echo "fuse3 libfuse3-dev" ;;
        dnf|yum) echo "fuse fuse3 fuse3-libs" ;;
        pacman)  echo "fuse3" ;;
        zypper)  echo "fuse3" ;;
        apk)     echo "fuse3 fuse3-dev" ;;
        xbps)    echo "fuse3" ;;
        emerge)  echo "sys-fs/fuse:3" ;;
        nix)     echo "nixpkgs.fuse3" ;;
        *)       echo "fuse3" ;;
    esac
}

get_rclone_packages() {
    case "$PKG_MANAGER" in
        emerge)  echo "net-misc/rclone" ;;
        nix)     echo "nixpkgs.rclone" ;;
        *)       echo "rclone" ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
#  ANSI COLOUR PALETTE
# ─────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m';    BRED='\033[1;31m'
GREEN='\033[0;32m';  BGREEN='\033[1;32m'
YELLOW='\033[0;33m'; BYELLOW='\033[1;33m'
BLUE='\033[0;34m';   BBLUE='\033[1;34m'
MAGENTA='\033[0;35m';BMAGENTA='\033[1;35m'
CYAN='\033[0;36m';   BCYAN='\033[1;36m'
WHITE='\033[0;37m';  BWHITE='\033[1;37m'
BOLD='\033[1m';      DIM='\033[2m'
ITALIC='\033[3m';    UNDERLINE='\033[4m'
RESET='\033[0m'

# ─────────────────────────────────────────────────────────────────────────────
#  LOGGING HELPERS
# ─────────────────────────────────────────────────────────────────────────────
log_info()    { echo -e "${BCYAN}[INFO]${RESET}    $*" | tee -a "$LOG_FILE"; }
log_ok()      { echo -e "${BGREEN}[OK]${RESET}      $*" | tee -a "$LOG_FILE"; }
log_warn()    { echo -e "${BYELLOW}[WARN]${RESET}    $*" | tee -a "$LOG_FILE"; }
log_error()   { echo -e "${BRED}[ERROR]${RESET}   $*" | tee -a "$LOG_FILE" >&2; }
log_step()    { echo -e "${BMAGENTA}[STEP]${RESET}    $*" | tee -a "$LOG_FILE"; }
log_debug()   { [[ "${DEBUG:-0}" == "1" ]] && echo -e "${DIM}[DEBUG]   $*${RESET}" >> "$LOG_FILE"; }
log_raw()     { echo -e "$*"; }

# ─────────────────────────────────────────────────────────────────────────────
#  SPINNER / PROGRESS
# ─────────────────────────────────────────────────────────────────────────────
_spinner_pid=""

spinner_start() {
    local msg="${1:-Working...}"
    local frames=('⣾' '⣽' '⣻' '⢿' '⡿' '⣟' '⣯' '⣷')
    echo -ne "\n${BCYAN}"
    (
        i=0
        while true; do
            printf "\r  ${frames[$((i % 8))]}  %s " "$msg"
            (( i++ )) || true
            sleep 0.1
        done
    ) &
    _spinner_pid=$!
    disown "$_spinner_pid" 2>/dev/null || true
}

spinner_stop() {
    if [[ -n "$_spinner_pid" ]]; then
        kill "$_spinner_pid" 2>/dev/null || true
        wait "$_spinner_pid" 2>/dev/null || true
        _spinner_pid=""
        printf "\r${RESET}%-60s\r" " "
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  BANNER
# ─────────────────────────────────────────────────────────────────────────────
print_banner() {
    clear
    echo -e "${BBLUE}"
    cat << 'EOF'
  ╔═══════════════════════════════════════════════════════════════════╗
  ║                                                                   ║
  ║   ██████╗  ██████╗██╗      ██████╗ ███╗   ██╗███████╗           ║
  ║   ██╔══██╗██╔════╝██║     ██╔═══██╗████╗  ██║██╔════╝           ║
  ║   ██████╔╝██║     ██║     ██║   ██║██╔██╗ ██║█████╗             ║
  ║   ██╔══██╗██║     ██║     ██║   ██║██║╚██╗██║██╔══╝             ║
  ║   ██║  ██║╚██████╗███████╗╚██████╔╝██║ ╚████║███████╗           ║
  ║   ╚═╝  ╚═╝ ╚═════╝╚══════╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝          ║
  ║                                                                   ║
  ║        Linux Rclone Local Mount Manager  v4.0.0                  ║
  ║        github.com/ShoumikBalaSomu/Fedora-Rclone-Local-Mount     ║
  ╚═══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${RESET}"
}

# ─────────────────────────────────────────────────────────────────────────────
#  DIVIDER / SECTION HEADER
# ─────────────────────────────────────────────────────────────────────────────
section() {
    echo -e "\n${BBLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "  ${BOLD}${BCYAN}$*${RESET}"
    echo -e "${BBLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
}

hr() {
    echo -e "${DIM}  ───────────────────────────────────────────────────────────────────${RESET}"
}

# ─────────────────────────────────────────────────────────────────────────────
#  PROMPT HELPERS
# ─────────────────────────────────────────────────────────────────────────────
ask() {
    # ask <variable_name> <prompt> [default]
    local var="$1" prompt="$2" default="${3:-}"
    local display_default=""
    [[ -n "$default" ]] && display_default=" ${DIM}[${default}]${RESET}"
    echo -ne "  ${BYELLOW}?${RESET}  ${BOLD}${prompt}${RESET}${display_default}: "
    read -r "$var"
    # If empty and default provided, assign default
    if [[ -z "${!var}" && -n "$default" ]]; then
        printf -v "$var" '%s' "$default"
    fi
}

ask_yn() {
    # ask_yn <prompt> <default y|n>  → returns 0 (yes) or 1 (no)
    local prompt="$1" default="${2:-n}"
    local yn_hint
    if [[ "$default" == "y" ]]; then yn_hint="${BGREEN}Y${RESET}/${DIM}n${RESET}"; else yn_hint="${DIM}y${RESET}/${BGREEN}N${RESET}"; fi
    echo -ne "  ${BYELLOW}?${RESET}  ${BOLD}${prompt}${RESET} [${yn_hint}]: "
    local ans; read -r ans
    ans="${ans:-$default}"
    [[ "${ans,,}" == "y" ]]
}

pause() {
    echo -ne "\n  ${DIM}Press ${RESET}${BOLD}[Enter]${RESET}${DIM} to continue...${RESET}"
    read -r
}

pick_from_list() {
    # pick_from_list <variable> <prompt> <item1> <item2> ...
    local var="$1"; shift
    local prompt="$1"; shift
    local items=("$@")
    echo -e "\n  ${BOLD}${prompt}${RESET}\n"
    local i=1
    for item in "${items[@]}"; do
        echo -e "    ${BCYAN}${i})${RESET}  ${item}"
        (( i++ )) || true
    done
    echo ""
    local choice
    while true; do
        ask choice "Enter number (1-${#items[@]})"
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#items[@]} )); then
            printf -v "$var" '%s' "${items[$((choice-1))]}"
            return 0
        fi
        log_warn "Invalid choice. Please enter a number between 1 and ${#items[@]}."
    done
}

# ─────────────────────────────────────────────────────────────────────────────
#  INIT — Ensure dirs / config file exist
# ─────────────────────────────────────────────────────────────────────────────
init_config() {
    mkdir -p "$CONFIG_DIR" "$DEFAULT_MOUNT_BASE" "$SYSTEMD_USER_DIR"
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << 'CONF'
# Linux Rclone Local Mount Manager — Saved Mounts
# Format: NAME|REMOTE|MOUNTPOINT|VFS_CACHE|READ_ONLY|EXTRA_FLAGS|AUTOMOUNT
# ─────────────────────────────────────────────────
CONF
        log_debug "Config file created at $CONFIG_FILE"
    fi
    # Create log with header if new
    if [[ ! -f "$LOG_FILE" ]]; then
        echo "# Rclone Mounter Log — started $(date)" > "$LOG_FILE"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  DEPENDENCY CHECK
# ─────────────────────────────────────────────────────────────────────────────
check_dependencies() {
    section "Dependency Check"

    # Show detected distro info
    echo -e "  ${BOLD}Distro:${RESET}          ${DISTRO_NAME}"
    echo -e "  ${BOLD}Package Manager:${RESET} ${PKG_MANAGER:-none detected}"
    hr
    echo ""

    local missing=()
    # Check core commands (cross-distro)
    local -A dep_cmds=(
        [rclone]="rclone"
        [fusermount3]="fusermount3"
        [systemctl]="systemctl"
    )

    for dep in rclone fusermount3 systemctl; do
        if command -v "$dep" &>/dev/null; then
            echo -e "  ${BGREEN}✓${RESET}  ${dep}"
        else
            missing+=("$dep")
            echo -e "  ${BRED}✗${RESET}  ${dep}"
        fi
    done

    # Also check if fuse kernel module is available
    if [[ -e /dev/fuse ]]; then
        echo -e "  ${BGREEN}✓${RESET}  /dev/fuse (FUSE kernel support)"
    else
        echo -e "  ${BYELLOW}~${RESET}  /dev/fuse (not found — may need to load fuse module)"
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        log_warn "Missing: ${missing[*]}"

        if [[ -z "$PKG_MANAGER" ]]; then
            log_error "No supported package manager detected. Please install manually: rclone fuse3"
            echo -e "  ${DIM}See https://rclone.org/install/ for rclone installation instructions${RESET}"
            exit 1
        fi

        if ask_yn "Auto-install missing dependencies via ${PKG_MANAGER}?" "y"; then
            spinner_start "Installing dependencies via ${PKG_MANAGER}..."
            local install_ok=true
            # Install rclone if missing
            if ! command -v rclone &>/dev/null; then
                local rclone_pkgs
                rclone_pkgs=$(get_rclone_packages)
                read -ra _rpkgs <<< "$rclone_pkgs"
                install_packages "${_rpkgs[@]}" || install_ok=false
            fi
            # Install fuse if missing
            if ! command -v fusermount3 &>/dev/null; then
                local fuse_pkgs
                fuse_pkgs=$(get_fuse_packages)
                read -ra _fpkgs <<< "$fuse_pkgs"
                install_packages "${_fpkgs[@]}" || install_ok=false
            fi
            spinner_stop
            if [[ "$install_ok" == false ]]; then
                log_error "Some packages failed to install. Check log: ${LOG_FILE}"
                echo -e "  ${DIM}You can also install rclone via: curl https://rclone.org/install.sh | sudo bash${RESET}"
            fi
            # Reload path
            hash -r
        else
            log_error "Cannot proceed without required dependencies."
            exit 1
        fi
    fi

    # systemctl is optional — warn but don't block on non-systemd systems
    if ! command -v systemctl &>/dev/null; then
        echo ""
        log_warn "systemd not detected. Auto-mount at boot will not be available."
        echo -e "  ${DIM}The script will still work for manual mounting.${RESET}"
    fi

    # Ensure fuse userspace access
    if [[ -f /etc/fuse.conf ]] && ! grep -qE '^\s*user_allow_other' /etc/fuse.conf 2>/dev/null; then
        log_warn "/etc/fuse.conf: 'user_allow_other' not set — --allow-other flag may fail."
        echo -e "  ${DIM}Run: sudo sh -c 'echo user_allow_other >> /etc/fuse.conf'${RESET}"
    fi

    log_ok "All dependencies satisfied."
}

# ─────────────────────────────────────────────────────────────────────────────
#  LIST MOUNTED DRIVES
# ─────────────────────────────────────────────────────────────────────────────
list_mounts() {
    section "Currently Mounted Rclone Drives"

    # Only match genuine rclone FUSE mounts (type fuse.rclone)
    # This excludes system mounts like fusectl, gvfsd-fuse, portal, etc.
    local mounted_lines
    mounted_lines=$(mount 2>/dev/null | grep 'type fuse\.rclone' || true)

    if [[ -z "$mounted_lines" ]]; then
        echo -e "  ${YELLOW}No rclone drives are currently mounted.${RESET}\n"
    else
        # Table header
        printf "\n  ${BOLD}%-22s %-38s %-12s %-8s %-10s${RESET}\n" "REMOTE" "MOUNTPOINT" "VFS CACHE" "MODE" "STATUS"
        hr

        while IFS= read -r line; do
            # mount output: <remote> on <mp> type fuse.rclone (options)
            local remote mp opts
            remote=$(echo "$line" | awk '{print $1}')
            mp=$(echo "$line"    | awk '{print $3}')
            opts=$(echo "$line"  | grep -o '([^)]*)' | head -1)
            # Extract vfs-cache-mode from options if present
            local vfs_disp
            vfs_disp=$(echo "$opts" | grep -oP 'vfs_cache_mode=[^,)]+' || echo "")
            [[ -z "$vfs_disp" ]] && vfs_disp="-"
            # Detect rw vs ro from mount options
            local mode_str
            if echo "$opts" | grep -q '\bro\b'; then
                mode_str="${BRED}RO${RESET}"
            else
                mode_str="${BGREEN}RW${RESET}"
            fi
            if ls "$mp" &>/dev/null 2>&1; then
                local status_str="${BGREEN}● Active${RESET}"
            else
                local status_str="${BRED}✗ Error${RESET}"
            fi
            printf "  ${BCYAN}%-22s${RESET} ${WHITE}%-38s${RESET} ${DIM}%-12s${RESET} %b    %b\n" \
                "$remote" "$mp" "$vfs_disp" "$mode_str" "$status_str"
        done <<< "$mounted_lines"

        hr
        echo ""
    fi

    # Always show saved profiles table
    if [[ -f "$CONFIG_FILE" ]]; then
        local count=0
        echo -e "  ${BOLD}Saved mount profiles:${RESET}\n"
        printf "  ${BOLD}%-20s %-38s %-10s %-10s${RESET}\n" "NAME" "MOUNTPOINT" "VFS CACHE" "AUTOMOUNT"
        hr
        while IFS='|' read -r name remote mp vfs ro extra auto; do
            [[ "$name" =~ ^#.*$ || -z "$name" ]] && continue
            # Check if this profile is currently mounted
            local mp_status=""
            if mount 2>/dev/null | grep -q "type fuse\.rclone" && \
               mount 2>/dev/null | grep "type fuse\.rclone" | awk '{print $3}' | grep -qxF "$mp"; then
                mp_status=" ${BGREEN}[mounted]${RESET}"
            fi
            local auto_flag="${DIM}No${RESET}"
            [[ "$auto" == "yes" ]] && auto_flag="${BGREEN}Yes${RESET}"
            printf "  ${BMAGENTA}%-20s${RESET} %-38s ${BCYAN}%-10s${RESET} %b%b\n" \
                "$name" "$mp" "$vfs" "$auto_flag" "$mp_status"
            (( count++ )) || true
        done < "$CONFIG_FILE"
        hr
        echo -e "  ${DIM}Total saved profiles: ${BOLD}${count}${RESET}\n"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  CONFIGURE A NEW RCLONE REMOTE
# ─────────────────────────────────────────────────────────────────────────────
configure_remote() {
    section "Configure New Rclone Remote"

    echo -e "  ${DIM}This will launch the interactive rclone config wizard.${RESET}"
    echo -e "  ${DIM}You can set up Google Drive, OneDrive, Dropbox, S3, SFTP, and more.${RESET}\n"

    local remote_name
    ask remote_name "Enter a custom name for this remote (e.g. gdrive, myonedrive)"
    # Sanitise
    remote_name="${remote_name//[^a-zA-Z0-9_-]/}"
    if [[ -z "$remote_name" ]]; then
        log_error "Remote name cannot be empty."
        return 1
    fi

    log_info "Launching rclone config for remote: ${BOLD}${remote_name}${RESET}"
    echo -e "  ${YELLOW}When prompted for the name of the new remote, enter: ${BOLD}${remote_name}${RESET}"
    echo ""
    pause

    rclone config

    # Verify the remote was created
    if rclone listremotes 2>/dev/null | grep -q "^${remote_name}:"; then
        log_ok "Remote '${remote_name}' configured successfully!"
    else
        log_warn "Remote '${remote_name}' was not found after config. You can re-run this step."
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  MOUNT DRIVE — MAIN FLOW
# ─────────────────────────────────────────────────────────────────────────────
mount_drive() {
    section "Mount a Cloud Drive"

    # ── 1. Pick remote ──────────────────────────────────────────────────────
    local remotes
    mapfile -t remotes < <(rclone listremotes 2>/dev/null | sed 's/:$//' || true)

    if [[ ${#remotes[@]} -eq 0 ]]; then
        log_warn "No rclone remotes found. Please configure one first."
        if ask_yn "Configure a new remote now?" "y"; then
            configure_remote
            mapfile -t remotes < <(rclone listremotes 2>/dev/null | sed 's/:$//' || true)
        else
            return
        fi
    fi

    local chosen_remote
    pick_from_list chosen_remote "Select a remote to mount:" "${remotes[@]}"
    log_info "Selected remote: ${BOLD}${chosen_remote}${RESET}"

    # ── 2. Remote sub-path (optional) ──────────────────────────────────────
    local remote_path
    ask remote_path "Remote sub-path to mount (leave blank for root)" ""
    local full_remote="${chosen_remote}:${remote_path}"

    # ── 3. Mount point ──────────────────────────────────────────────────────
    local default_mp="${DEFAULT_MOUNT_BASE}/${chosen_remote}"
    local mountpoint
    ask mountpoint "Local mount directory" "$default_mp"

    if [[ -z "$mountpoint" ]]; then
        log_error "Mountpoint cannot be empty."
        return 1
    fi

    # Expand ~
    mountpoint="${mountpoint/#\~/$HOME}"

    # Check if already mounted
    if mount | grep -q " ${mountpoint} "; then
        log_warn "Something is already mounted at ${mountpoint}."
        if ! ask_yn "Unmount and remount?" "n"; then
            return
        fi
        fusermount3 -u "$mountpoint" 2>/dev/null || fusermount -u "$mountpoint" 2>/dev/null || true
    fi

    mkdir -p "$mountpoint"
    log_info "Mountpoint: ${BOLD}${mountpoint}${RESET}"

    # ── 4. VFS Cache mode ───────────────────────────────────────────────────
    section "Mount Options"
    echo -e "  ${BOLD}VFS Cache Mode${RESET} — controls local caching behaviour:\n"
    echo -e "    ${BCYAN}1)${RESET}  ${BOLD}off${RESET}      — No caching (lowest disk use, may break some apps)"
    echo -e "    ${BCYAN}2)${RESET}  ${BOLD}minimal${RESET}  — Cache only read-open files"
    echo -e "    ${BCYAN}3)${RESET}  ${BOLD}writes${RESET}   — Cache files opened for writing (recommended for most)"
    echo -e "    ${BCYAN}4)${RESET}  ${BOLD}full${RESET}     — Full read/write cache (best compatibility, offline access)\n"

    local vfs_choice vfs_cache
    ask vfs_choice "Choose VFS cache mode" "4"
    case "$vfs_choice" in
        1) vfs_cache="off" ;;
        2) vfs_cache="minimal" ;;
        3) vfs_cache="writes" ;;
        *) vfs_cache="full" ;;
    esac

    # ── 5. Read-write / Read-only ──────────────────────────────────────────
    local read_only="false"
    echo -e "  ${BOLD}Mount Access Mode:${RESET}\n"
    echo -e "    ${BGREEN}READ-WRITE (default)${RESET} — You can create, edit, and delete files."
    echo -e "    ${BYELLOW}READ-ONLY${RESET}           — Files are view-only; no edits allowed.\n"
    if ask_yn "Mount as read-only? (say NO to allow editing files)" "n"; then
        read_only="true"
        echo -e "\n  ${BRED}⚠  WARNING:${RESET} ${BOLD}Read-only mode selected.${RESET}"
        echo -e "  ${DIM}You will NOT be able to create, edit, or delete files on this mount.${RESET}"
        echo -e "  ${DIM}To change later, re-run this script and remount as read-write.${RESET}\n"
    else
        echo -e "\n  ${BGREEN}✓${RESET}  ${BOLD}Read-write mode${RESET} — you can edit files on this mount.\n"
    fi

    # ── 6. Allow other users — SAFE: check /etc/fuse.conf first ─────────────
    local allow_other_flag=false
    if grep -qE '^\s*user_allow_other' /etc/fuse.conf 2>/dev/null; then
        # fuse.conf already has user_allow_other — safe to offer the option
        if ask_yn "Allow other system users to access this mount?" "n"; then
            allow_other_flag=true
        fi
    else
        echo -e "\n  ${BYELLOW}[NOTE]${RESET}  ${BOLD}--allow-other${RESET} is disabled."
        echo -e "  ${DIM}/etc/fuse.conf does not contain 'user_allow_other'.${RESET}"
        echo -e "  ${DIM}Without it, rclone mount will fail with this flag.${RESET}"
        if ask_yn "Auto-enable user_allow_other in /etc/fuse.conf now? (needs sudo)" "n"; then
            if sudo sh -c 'echo "user_allow_other" >> /etc/fuse.conf'; then
                log_ok "user_allow_other enabled in /etc/fuse.conf"
                if ask_yn "Allow other system users to access this mount?" "n"; then
                    allow_other_flag=true
                fi
            else
                log_warn "Could not edit /etc/fuse.conf — skipping --allow-other"
            fi
        else
            log_info "Skipping --allow-other (not enabled in /etc/fuse.conf)"
        fi
    fi

    # ── 7. Extra rclone flags ───────────────────────────────────────────────
    local extra_flags
    ask extra_flags "Any extra rclone mount flags (blank for none)" ""

    # ── 8. Mount name / profile name ───────────────────────────────────────
    local default_name="${chosen_remote}"
    # Warn if a profile with the same mountpoint already exists
    if [[ -f "$CONFIG_FILE" ]] && grep -v '^#' "$CONFIG_FILE" | awk -F'|' '{print $3}' | grep -qxF "$mountpoint"; then
        log_warn "A saved profile already uses mountpoint '${mountpoint}'."
        echo -e "  ${DIM}Consider using a different name or mountpoint to avoid confusion.${RESET}"
    fi
    local profile_name
    ask profile_name "Save profile as name" "$default_name"
    profile_name="${profile_name//[^a-zA-Z0-9_-]/}"
    if [[ -z "$profile_name" ]]; then
        profile_name="${chosen_remote}-$(date +%s | tail -c 5)"
    fi

    # ── 9. Automount at boot ────────────────────────────────────────────────
    local automount="no"
    if ask_yn "Enable auto-mount at every boot via systemd?" "y"; then
        automount="yes"
    fi

    # ── 10. BUILD rclone command safely (array, no eval) ────────────────────
    local -a mount_cmd=(
        rclone mount
        "${full_remote}"
        "${mountpoint}"
        --vfs-cache-mode "${vfs_cache}"
        --daemon
        --log-file "${LOG_FILE}"
    )
    # Sync-optimised VFS flags: local writes are flushed to cloud quickly,
    # remote changes are detected promptly, and cached data stays fresh.
    if [[ "$vfs_cache" == "full" || "$vfs_cache" == "writes" ]]; then
        mount_cmd+=(
            --poll-interval 15s
            --dir-cache-time 5m
            --vfs-cache-max-age 24h
            --vfs-write-back 5s
            --vfs-cache-poll-interval 1m
            --attr-timeout 1s
            --vfs-read-ahead 128M
        )
    fi
    [[ "$read_only"       == "true" ]] && mount_cmd+=(--read-only)
    [[ "$allow_other_flag" == true  ]] && mount_cmd+=(--allow-other)
    # Split extra_flags safely into array words
    if [[ -n "$extra_flags" ]]; then
        read -ra _extra_arr <<< "$extra_flags"
        mount_cmd+=("${_extra_arr[@]}")
    fi

    echo -e "\n  ${DIM}Command to execute:${RESET}"
    echo -e "  ${ITALIC}${DIM}${mount_cmd[*]}${RESET}\n"

    if ask_yn "Proceed with mounting?" "y"; then
        spinner_start "Mounting ${full_remote}..."
        "${mount_cmd[@]}" >> "$LOG_FILE" 2>&1
        spinner_stop

        sleep 1
        # Verify using the precise fuse.rclone type check
        if mount 2>/dev/null | grep 'type fuse\.rclone' | awk '{print $3}' | grep -qxF "${mountpoint}"; then
            log_ok "Successfully mounted ${BOLD}${full_remote}${RESET} → ${BOLD}${mountpoint}${RESET}"
            # Show rw/ro status clearly
            local mount_opts
            mount_opts=$(mount 2>/dev/null | grep "${mountpoint}" | grep -o '([^)]*)' | head -1)
            if echo "$mount_opts" | grep -q '\bro\b'; then
                echo -e "  ${BYELLOW}📖 Mode: READ-ONLY${RESET} — files cannot be edited"
            else
                echo -e "  ${BGREEN}✏️  Mode: READ-WRITE${RESET} — files can be edited"
            fi
            # Quick write-access verification for rw mounts
            if [[ "$read_only" == "false" ]]; then
                local test_file="${mountpoint}/.rclone_write_test_$$"
                if touch "$test_file" 2>/dev/null; then
                    rm -f "$test_file" 2>/dev/null
                    log_ok "Write-access verified ✓"
                else
                    log_warn "Mount is rw but write test failed — check cloud permissions."
                fi
            fi
        else
            log_error "Mount failed. Check log: ${LOG_FILE}"
            tail -5 "$LOG_FILE" | while IFS= read -r l; do echo -e "  ${DIM}${l}${RESET}"; done
            return 1
        fi
    else
        log_info "Mount cancelled."
        return
    fi

    # ── 11. Save profile ─────────────────────────────────────────────────────
    local saved_allow=""
    [[ "$allow_other_flag" == true ]] && saved_allow="--allow-other"
    # Remove old entry with same name if any
    if [[ -f "$CONFIG_FILE" ]]; then
        grep -v "^${profile_name}|" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    fi
    echo "${profile_name}|${full_remote}|${mountpoint}|${vfs_cache}|${read_only}|${saved_allow} ${extra_flags}|${automount}" >> "$CONFIG_FILE"
    log_info "Profile '${profile_name}' saved to ${CONFIG_FILE}"

    # ── 12. Install systemd unit ─────────────────────────────────────────────
    if [[ "$automount" == "yes" ]]; then
        install_systemd_unit "$profile_name" "$full_remote" "$mountpoint" \
            "$vfs_cache" "$read_only" "$saved_allow" "$extra_flags"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  INSTALL SYSTEMD UNIT FOR AUTO-MOUNT
# ─────────────────────────────────────────────────────────────────────────────
install_systemd_unit() {
    local name="$1" remote="$2" mp="$3" vfs="$4" ro="$5" allow_other="$6" extra="$7"
    local unit_file="${SYSTEMD_USER_DIR}/rclone-${name}.service"

    local ro_flag=""
    [[ "$ro" == "true" ]] && ro_flag="--read-only"

    local rclone_path
    rclone_path=$(command -v rclone)

    # Build ExecStart command line
    local exec_start="${rclone_path} mount ${remote} ${mp}"
    exec_start+=" --config=%h/.config/rclone/rclone.conf"
    exec_start+=" --vfs-cache-mode ${vfs}"
    # Sync-optimised VFS flags: local writes flush quickly, remote changes detected
    if [[ "$vfs" == "full" || "$vfs" == "writes" ]]; then
        exec_start+=" --poll-interval 15s"
        exec_start+=" --dir-cache-time 5m"
        exec_start+=" --vfs-cache-max-age 24h"
        exec_start+=" --vfs-write-back 5s"
        exec_start+=" --vfs-cache-poll-interval 1m"
        exec_start+=" --attr-timeout 1s"
        exec_start+=" --vfs-read-ahead 128M"
    fi
    [[ -n "$ro_flag" ]]     && exec_start+=" ${ro_flag}"
    [[ -n "$allow_other" ]] && exec_start+=" ${allow_other}"
    [[ -n "$extra" ]]       && exec_start+=" ${extra}"
    exec_start+=" --log-file=${LOG_FILE}"
    exec_start+=" --log-level INFO"

    cat > "$unit_file" << UNIT
[Unit]
Description=Rclone Mount — ${name} (${remote})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStartPre=/bin/mkdir -p ${mp}
ExecStartPre=-/bin/fusermount3 -uz ${mp}
ExecStart=${exec_start}
ExecStop=/bin/fusermount3 -u ${mp}
Restart=on-failure
RestartSec=10s
Environment=RCLONE_LOG_LEVEL=INFO

[Install]
WantedBy=default.target
UNIT

    chmod 644 "$unit_file"
    systemctl --user daemon-reload
    systemctl --user enable "rclone-${name}.service" 2>/dev/null
    systemctl --user start  "rclone-${name}.service" 2>/dev/null || true

    log_ok "Systemd unit installed: ${unit_file}"
    log_ok "Service enabled for auto-mount at boot."

    # Ensure lingering is enabled (so user services run without login)
    if command -v loginctl &>/dev/null; then
        loginctl enable-linger "$(whoami)" 2>/dev/null || true
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  UNMOUNT DRIVE
# ─────────────────────────────────────────────────────────────────────────────
unmount_drive() {
    section "Unmount a Drive"

    # Build list — only genuine rclone FUSE mounts (type fuse.rclone)
    local mounted_mps=()
    while IFS= read -r line; do
        local mp
        mp=$(echo "$line" | awk '{print $3}')
        mounted_mps+=("$mp")
    done < <(mount 2>/dev/null | grep 'type fuse\.rclone' || true)

    if [[ ${#mounted_mps[@]} -eq 0 ]]; then
        log_warn "No rclone drives are currently mounted."
        pause
        return
    fi

    local target_mp
    pick_from_list target_mp "Select drive to unmount:" "${mounted_mps[@]}"

    if ask_yn "Unmount ${BOLD}${target_mp}${RESET}?" "y"; then
        spinner_start "Unmounting ${target_mp}..."
        if fusermount3 -u "$target_mp" 2>/dev/null || fusermount -u "$target_mp" 2>/dev/null; then
            spinner_stop
            log_ok "Successfully unmounted ${target_mp}"
        else
            spinner_stop
            log_warn "Normal unmount failed, trying lazy unmount..."
            fusermount3 -uz "$target_mp" 2>/dev/null \
                || fusermount -uz "$target_mp" 2>/dev/null \
                || umount -l "$target_mp" 2>/dev/null \
                || { log_error "Could not unmount ${target_mp}. Try: sudo umount -l ${target_mp}"; return 1; }
            log_ok "Lazy unmount of ${target_mp} succeeded."
        fi
    fi

    # Offer to disable systemd unit
    local unit_name=""
    if [[ -f "$CONFIG_FILE" ]]; then
        while IFS='|' read -r name _ mp _; do
            [[ "$mp" == "$target_mp" ]] && unit_name="$name" && break
        done < "$CONFIG_FILE"
    fi

    if [[ -n "$unit_name" ]]; then
        if ask_yn "Disable auto-mount unit for '${unit_name}'?" "n"; then
            systemctl --user disable --now "rclone-${unit_name}.service" 2>/dev/null || true
            log_ok "Auto-mount unit disabled."
        fi
    fi

    pause
}

# ─────────────────────────────────────────────────────────────────────────────
#  MANAGE SAVED PROFILES
# ─────────────────────────────────────────────────────────────────────────────
manage_profiles() {
    section "Manage Saved Profiles"

    local profiles=()
    if [[ -f "$CONFIG_FILE" ]]; then
        while IFS='|' read -r name remote mp vfs ro extra auto; do
            [[ "$name" =~ ^#.*$ || -z "$name" ]] && continue
            profiles+=("${name}  →  ${remote}  (${mp})")
        done < "$CONFIG_FILE"
    fi

    if [[ ${#profiles[@]} -eq 0 ]]; then
        log_warn "No saved profiles found."
        pause
        return
    fi

    echo -e "  ${BOLD}Saved Profiles:${RESET}\n"
    local i=1
    for p in "${profiles[@]}"; do
        echo -e "    ${BCYAN}${i})${RESET}  ${p}"
        (( i++ )) || true
    done

    echo -e "\n    ${BCYAN}d)${RESET}  Delete a profile"
    echo -e "    ${BCYAN}m)${RESET}  Mount a saved profile"
    echo -e "    ${BCYAN}b)${RESET}  Back"
    echo ""
    local choice; ask choice "Choice"

    case "${choice,,}" in
        d)
            local idx; ask idx "Profile number to delete"
            if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#profiles[@]} )); then
                # Get name of that profile
                local pname; pname=$(echo "${profiles[$((idx-1))]}" | awk '{print $1}')
                if ask_yn "Delete profile '${pname}'?" "n"; then
                    grep -v "^${pname}|" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
                    # Remove systemd unit if exists
                    local unit="${SYSTEMD_USER_DIR}/rclone-${pname}.service"
                    if [[ -f "$unit" ]]; then
                        systemctl --user disable --now "rclone-${pname}.service" 2>/dev/null || true
                        rm -f "$unit"
                        systemctl --user daemon-reload
                    fi
                    log_ok "Profile '${pname}' deleted."
                fi
            fi
            ;;
        m)
            local idx; ask idx "Profile number to mount"
            if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#profiles[@]} )); then
                local pname; pname=$(echo "${profiles[$((idx-1))]}" | awk '{print $1}')
                mount_saved_profile "$pname"
            fi
            ;;
        b|*) return ;;
    esac

    pause
}

mount_saved_profile() {
    local target_name="$1"
    while IFS='|' read -r name remote mp vfs ro extra auto; do
        [[ "$name" != "$target_name" ]] && continue
        # Build command array safely — no eval
        local -a mount_cmd=(
            rclone mount
            "${remote}"
            "${mp}"
            --vfs-cache-mode "${vfs}"
            --daemon
            --log-file "${LOG_FILE}"
        )
        # Sync-optimised VFS flags: local writes flush quickly, remote changes detected
        if [[ "$vfs" == "full" || "$vfs" == "writes" ]]; then
            mount_cmd+=(
                --poll-interval 15s
                --dir-cache-time 5m
                --vfs-cache-max-age 24h
                --vfs-write-back 5s
                --vfs-cache-poll-interval 1m
                --attr-timeout 1s
                --vfs-read-ahead 128M
            )
        fi
        [[ "$ro" == "true" ]] && mount_cmd+=(--read-only)
        # Split saved flags safely
        if [[ -n "$extra" ]]; then
            read -ra _extra_arr <<< "$extra"
            mount_cmd+=("${_extra_arr[@]}")
        fi
        mkdir -p "$mp"
        spinner_start "Mounting profile '${name}'..."
        "${mount_cmd[@]}" >> "$LOG_FILE" 2>&1
        spinner_stop
        sleep 1
        if mount 2>/dev/null | grep 'type fuse\.rclone' | awk '{print $3}' | grep -qxF "${mp}"; then
            log_ok "Mounted '${name}': ${remote} → ${mp}"
        else
            log_error "Mount failed for '${name}'. Check ${LOG_FILE}"
            tail -5 "$LOG_FILE" | while IFS= read -r l; do echo -e "  ${DIM}${l}${RESET}"; done
        fi
        return
    done < "$CONFIG_FILE"
    log_error "Profile '${target_name}' not found."
}

# ─────────────────────────────────────────────────────────────────────────────
#  VIEW LOG
# ─────────────────────────────────────────────────────────────────────────────
view_log() {
    section "Rclone Mounter Log (last 40 lines)"
    if [[ -f "$LOG_FILE" ]]; then
        tail -40 "$LOG_FILE" | while IFS= read -r line; do
            if echo "$line" | grep -qi "error"; then
                echo -e "  ${BRED}${line}${RESET}"
            elif echo "$line" | grep -qi "warn"; then
                echo -e "  ${BYELLOW}${line}${RESET}"
            elif echo "$line" | grep -qi "info\|ok"; then
                echo -e "  ${BCYAN}${line}${RESET}"
            else
                echo -e "  ${DIM}${line}${RESET}"
            fi
        done
    else
        echo -e "  ${DIM}No log file found.${RESET}"
    fi
    echo ""
    pause
}

# ─────────────────────────────────────────────────────────────────────────────
#  SYSTEM STATUS
# ─────────────────────────────────────────────────────────────────────────────
show_status() {
    section "System Status"

    echo -e "  ${BOLD}Linux distro:${RESET}    ${DISTRO_NAME} (${DISTRO_ID})"
    echo -e "  ${BOLD}Package manager:${RESET} ${PKG_MANAGER:-none}"
    echo -e "  ${BOLD}Rclone version:${RESET}  $(rclone --version 2>/dev/null | head -1 || echo 'not found')"
    echo -e "  ${BOLD}Config file:${RESET}     ${CONFIG_FILE}"
    echo -e "  ${BOLD}Log file:${RESET}        ${LOG_FILE}"
    echo -e "  ${BOLD}Default mount base:${RESET} ${DEFAULT_MOUNT_BASE}"
    if command -v systemctl &>/dev/null; then
        echo -e "  ${BOLD}Systemd units dir:${RESET}  ${SYSTEMD_USER_DIR}"
    else
        echo -e "  ${BOLD}Init system:${RESET}     ${DIM}non-systemd (auto-mount unavailable)${RESET}"
    fi
    echo ""

    # Active systemd units
    echo -e "  ${BOLD}Active rclone systemd units:${RESET}"
    hr
    systemctl --user list-units "rclone-*.service" --no-pager 2>/dev/null || echo -e "  ${DIM}None${RESET}"
    echo ""

    # Disk usage of mountpoints
    echo -e "  ${BOLD}Mount disk usage:${RESET}"
    hr
    while IFS='|' read -r name _ mp _; do
        [[ "$name" =~ ^#.*$ || -z "$name" ]] && continue
        if mount | grep -q "${mp}"; then
            df -h "$mp" 2>/dev/null | tail -1 | awk -v n="$name" '{printf "  %-20s  Total: %-8s  Used: %-8s  Free: %s\n", n, $2, $3, $4}'
        fi
    done < "$CONFIG_FILE" 2>/dev/null || true

    pause
}

# ─────────────────────────────────────────────────────────────────────────────
#  UNINSTALL
# ─────────────────────────────────────────────────────────────────────────────
uninstall() {
    section "⚠  Uninstall / Clean Up"

    log_warn "This will:"
    echo -e "   ${RED}•${RESET} Stop and disable all rclone systemd units"
    echo -e "   ${RED}•${RESET} Unmount all rclone drives"
    echo -e "   ${RED}•${RESET} Remove all saved profiles"
    echo -e "   ${RED}•${RESET} Remove systemd unit files"
    echo ""

    if ! ask_yn "Are you absolutely sure?" "n"; then
        log_info "Uninstall cancelled."
        return
    fi

    # Stop units
    for unit in "${SYSTEMD_USER_DIR}"/rclone-*.service; do
        [[ -f "$unit" ]] || continue
        local uname; uname=$(basename "$unit")
        systemctl --user disable --now "$uname" 2>/dev/null || true
        rm -f "$unit"
    done
    systemctl --user daemon-reload 2>/dev/null || true

    # Unmount all — only genuine rclone mounts
    mount 2>/dev/null | grep 'type fuse\.rclone' | awk '{print $3}' | while read -r mp; do
        fusermount3 -uz "$mp" 2>/dev/null || fusermount -uz "$mp" 2>/dev/null || true
    done

    # Remove config
    rm -f "$CONFIG_FILE" "$LOG_FILE"

    log_ok "Cleanup complete. Rclone itself was NOT removed (use: sudo dnf remove rclone)."
    pause
}

# ─────────────────────────────────────────────────────────────────────────────
#  HELP / ABOUT
# ─────────────────────────────────────────────────────────────────────────────
show_help() {
    section "Help & About"
    cat << 'HELP'
  COMMANDS (non-interactive / scriptable):
  ─────────────────────────────────────────────────────────────────────
  rclone-mount.sh --list            List mounted drives
  rclone-mount.sh --mount-all       Mount all saved profiles
  rclone-mount.sh --unmount-all     Unmount all rclone drives
  rclone-mount.sh --status          Show system status
  rclone-mount.sh --check           Check dependencies only

  VFS CACHE MODES:
  ─────────────────────────────────────────────────────────────────────
  off       No caching (fastest, least compatible)
  minimal   Only cache files opened for read
  writes    Cache files open for writing (good default)
  full      Full read/write cache (best compatibility, uses most disk)

  SUPPORTED CLOUDS (via rclone):
  ─────────────────────────────────────────────────────────────────────
  Google Drive, OneDrive, Dropbox, Amazon S3, Backblaze B2,
  SFTP, WebDAV, Box, pCloud, Mega, and 70+ others.

  LINKS:
  ─────────────────────────────────────────────────────────────────────
  GitHub  : https://github.com/ShoumikBalaSomu/Fedora-Rclone-Local-Mount
  Rclone  : https://rclone.org/docs/
  Systemd : https://wiki.archlinux.org/title/Rclone
HELP
    echo ""
    pause
}

# ─────────────────────────────────────────────────────────────────────────────
#  NON-INTERACTIVE CLI MODE
# ─────────────────────────────────────────────────────────────────────────────
cli_mode() {
    case "${1:-}" in
        --list)
            init_config
            list_mounts
            ;;
        --mount-all)
            init_config
            if [[ ! -f "$CONFIG_FILE" ]]; then
                echo "No config file found."; exit 1
            fi
            while IFS='|' read -r name _ _ _ _ _ _; do
                [[ "$name" =~ ^#.*$ || -z "$name" ]] && continue
                mount_saved_profile "$name"
            done < "$CONFIG_FILE"
            ;;
        --unmount-all)
            init_config
            mount | grep -E 'fuse\.rclone|rclone' | awk '{print $3}' | while read -r mp; do
                fusermount3 -uz "$mp" 2>/dev/null || fusermount -uz "$mp" 2>/dev/null && echo "Unmounted: $mp"
            done
            ;;
        --status)
            init_config
            show_status
            ;;
        --check)
            init_config
            check_dependencies
            ;;
        --help|-h)
            show_help
            ;;
        "")
            return 1  # No CLI args; fall through to interactive
            ;;
        *)
            echo "Unknown option: ${1}. Use --help for usage."
            exit 1
            ;;
    esac
    exit 0
}

# ─────────────────────────────────────────────────────────────────────────────
#  MAIN MENU
# ─────────────────────────────────────────────────────────────────────────────
main_menu() {
    while true; do
        print_banner
        echo -e "  ${BOLD}${BWHITE}Main Menu${RESET}\n"
        echo -e "  ${BCYAN} 1 )${RESET}  📋  List mounted drives"
        echo -e "  ${BCYAN} 2 )${RESET}  ☁   Mount a cloud drive"
        echo -e "  ${BCYAN} 3 )${RESET}  ⏏   Unmount a drive"
        echo -e "  ${BCYAN} 4 )${RESET}  🗂   Manage saved profiles"
        echo -e "  ${BCYAN} 5 )${RESET}  ⚙   Configure new rclone remote"
        echo -e "  ${BCYAN} 6 )${RESET}  📊  System status & disk usage"
        echo -e "  ${BCYAN} 7 )${RESET}  🔍  Check dependencies"
        echo -e "  ${BCYAN} 8 )${RESET}  📄  View log"
        echo -e "  ${BCYAN} 9 )${RESET}  ❓  Help & About"
        echo -e "  ${BRED} 0 )${RESET}  🗑   Uninstall / Clean up"
        echo -e "  ${BRED} q )${RESET}  ✖   Quit"
        echo ""
        hr
        ask choice "Select option"
        echo ""

        case "${choice,,}" in
            1) list_mounts;          pause ;;
            2) mount_drive ;;
            3) unmount_drive ;;
            4) manage_profiles ;;
            5) configure_remote ;;
            6) show_status ;;
            7) check_dependencies;   pause ;;
            8) view_log ;;
            9) show_help ;;
            0) uninstall ;;
            q|quit|exit) echo -e "\n  ${BGREEN}Goodbye!${RESET}\n"; exit 0 ;;
            *) log_warn "Invalid option '${choice}'" ;;
        esac
    done
}

# ─────────────────────────────────────────────────────────────────────────────
#  ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────
main() {
    # Detect Linux distro and package manager early
    detect_distro
    detect_pkg_manager

    # Route CLI args first
    if [[ $# -gt 0 ]]; then
        init_config
        cli_mode "$@"
    fi

    # Interactive TUI
    init_config
    check_dependencies
    pause
    main_menu
}

main "$@"
