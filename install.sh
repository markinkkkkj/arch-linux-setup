#!/usr/bin/env bash

set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'

info()    { echo -e "${BLUE}[i]$1${NC}"; }
warn()    { echo -e "${YELLOW}[!]$1${NC}"; }
success() { echo -e "${GREEN}[✓]$1${NC}"; }
error()   { echo -e "${RED}[✗]$1${NC}"; }

# ---------------------------------------------------------------------------
# Global state
# ---------------------------------------------------------------------------

DRY_RUN=false
ASSUME_YES=false
ONLY_GROUPS=()
SKIP_GROUPS=()
FAILED_PKGS=()
CLEANUP_DIRS=()
SUDO_KEEPALIVE_PID=""
LOG_FILE="$HOME/arch-setup-$(date +%Y%m%d-%H%M%S).log"

# ---------------------------------------------------------------------------
# Error handling / cleanup
# ---------------------------------------------------------------------------

on_error() {
    local exit_code=$?
    error "Command failed: \"${BASH_COMMAND}\" (line ${BASH_LINENO[0]}), exit code ${exit_code}."
}

cleanup() {
    if [[ -n "$SUDO_KEEPALIVE_PID" ]]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
    local d
    for d in "${CLEANUP_DIRS[@]}"; do
        [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
    done
}

trap on_error ERR
trap cleanup EXIT

# ---------------------------------------------------------------------------
# CLI flags
# ---------------------------------------------------------------------------

usage() {
    cat <<'EOF'
Usage: install.sh [options]

Options:
  --dry-run              Show what would be done, without installing or changing anything.
  --only=GROUP[,GROUP..] Run only the given groups.
  --skip=GROUP[,GROUP..] Skip the given groups.
  --yes                  Don't ask anything; assume the default answer for every prompt.
  --help                 Show this help and exit.
EOF
}

parse_args() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            --dry-run) DRY_RUN=true ;;
            --only=*) IFS=',' read -r -a ONLY_GROUPS <<< "${arg#--only=}" ;;
            --skip=*) IFS=',' read -r -a SKIP_GROUPS <<< "${arg#--skip=}" ;;
            --yes) ASSUME_YES=true ;;
            --help) usage; exit 0 ;;
            *)
                error "Unknown option: $arg"
                usage
                exit 1
                ;;
        esac
    done
}

group_enabled() {
    local group="$1" g

    if [[ ${#ONLY_GROUPS[@]} -gt 0 ]]; then
        local in_only=false
        for g in "${ONLY_GROUPS[@]}"; do
            [[ "$g" == "$group" ]] && in_only=true
        done
        [[ "$in_only" == true ]] || return 1
    fi

    for g in "${SKIP_GROUPS[@]}"; do
        [[ "$g" == "$group" ]] && return 1
    done

    return 0
}

# ---------------------------------------------------------------------------
# Interactive prompt
#
# The script runs from the cloned repository (no longer via curl | bash), so
# stdin is the normal terminal — a plain `read` already works.
# ---------------------------------------------------------------------------

confirm() {
    local prompt="$1" default="${2:-n}" reply hint

    if $ASSUME_YES; then
        return 0
    fi

    [[ "$default" == "y" ]] && hint="[Y/n]" || hint="[y/N]"

    read -r -p "$prompt $hint " reply
    reply="${reply:-$default}"
    [[ "$reply" =~ ^[Yy]$ ]]
}

# ---------------------------------------------------------------------------
# Repository awareness — the script can be invoked from any directory
# (e.g. ~/linux-setup/install.sh), so we resolve its own path, following
# symlinks, to use as the root for any relative path.
# ---------------------------------------------------------------------------

resolve_script_dir() {
    local source dir
    source="${BASH_SOURCE[0]}"
    while [[ -h "$source" ]]; do
        dir="$(cd -P "$(dirname "$source")" >/dev/null 2>&1 && pwd)"
        source="$(readlink "$source")"
        [[ "$source" != /* ]] && source="$dir/$source"
    done
    cd -P "$(dirname "$source")" >/dev/null 2>&1 && pwd
}

SCRIPT_DIR="$(resolve_script_dir)"

# ---------------------------------------------------------------------------
# Logging — duplicates all output to a file, stripped of color codes.
# ---------------------------------------------------------------------------

setup_logging() {
    exec > >(tee >(sed -E 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE")) 2>&1
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

check_arch() {
    if [[ ! -f /etc/os-release ]]; then
        error "Could not determine which OS is being used."
        exit 1
    fi

    . /etc/os-release

    if [[ "$ID" != "arch" && "$ID_LIKE" != *arch* ]]; then
        error "This script is meant to be used on Arch or Arch-based distros (current distro: ${PRETTY_NAME:-unknown})."
        exit 1
    fi
}

check_not_root() {
    if [[ $EUID -eq 0 ]]; then
        error "This script must be run as a normal user, not root."
        exit 1
    fi
}

check_repo() {
    if [[ ! -d "$SCRIPT_DIR/dotfiles" || ! -d "$SCRIPT_DIR/docs" ]]; then
        error "install.sh doesn't appear to be inside the expected repository (missing dotfiles/ and/or docs/ next to it in $SCRIPT_DIR)."
        exit 1
    fi

    if ! command -v git >/dev/null 2>&1 || ! git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        warn "Could not determine the current commit (git missing, or $SCRIPT_DIR is not a git repository)."
        return 0
    fi

    local commit
    commit="$(git -C "$SCRIPT_DIR" rev-parse --short HEAD)"
    info "Repository: $SCRIPT_DIR (commit $commit)"

    if [[ -n "$(git -C "$SCRIPT_DIR" status --porcelain)" ]]; then
        warn "Dirty working tree in $SCRIPT_DIR — there are uncommitted changes."
    fi
}

check_internet() {
    if ! curl -fsS --max-time 5 -o /dev/null "https://archlinux.org"; then
        error "No internet connection (failed to reach https://archlinux.org)."
        exit 1
    fi
}

check_pacman() {
    if [[ -f /var/lib/pacman/db.lck ]]; then
        error "Pacman is locked by another instance."
        exit 1
    fi
}

check_sudo() {
    if ! sudo -v; then
        error "No sudo privilege."
        exit 1
    fi
}

start_sudo_keepalive() {
    ( while true; do sudo -n -v; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
    SUDO_KEEPALIVE_PID=$!
}

check_disk_space() {
    local min_gb=15
    local target_dir="/var/cache/pacman/pkg"

    while [[ ! -d "$target_dir" ]]; do
        target_dir=$(dirname "$target_dir")
    done

    local avail_kb avail_gb
    avail_kb=$(df --output=avail "$target_dir" | tail -1)
    avail_gb=$((avail_kb / 1024 / 1024))

    if [[ $avail_gb -lt $min_gb ]]; then
        error "Not enough disk space on $target_dir (available: ${avail_gb}GB, required: ${min_gb}GB)."
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Installation helpers
# ---------------------------------------------------------------------------

system_upgrade() {
    if $DRY_RUN; then
        info "[dry-run] would run: sudo pacman -Syu --noconfirm"
        return 0
    fi

    info "Upgrading the system before installing (avoids a partial upgrade)..."
    sudo pacman -Syu --noconfirm
}

ensure_git() {
    if ! command -v git >/dev/null 2>&1; then
        info "git not found, installing it (required to clone from the AUR)..."
        sudo pacman -S --needed --noconfirm git
    fi
}

check_yay() {
    if command -v yay >/dev/null 2>&1; then
        return 0
    fi

    if $DRY_RUN; then
        info "[dry-run] would install yay (AUR helper)."
        return 0
    fi

    ensure_git

    local tmpdir
    tmpdir=$(mktemp -d)
    CLEANUP_DIRS+=("$tmpdir")

    pushd "$tmpdir" >/dev/null
    git clone https://aur.archlinux.org/yay.git
    pushd yay >/dev/null
    makepkg -si --noconfirm
    popd >/dev/null
    popd >/dev/null
}

# install_pkgs <array-name> [pacman|yay]
#
# Tries to install everything in one batch; if the batch fails (today a
# single wrong name takes down the whole array), it falls back to a
# package-by-package loop and accumulates failures in FAILED_PKGS instead of
# aborting the script.
install_pkgs() {
    local -n _pkgs_ref="$1"
    local manager="${2:-pacman}"
    local pkgs=("${_pkgs_ref[@]}")

    [[ ${#pkgs[@]} -eq 0 ]] && return 0

    if $DRY_RUN; then
        info "[dry-run] ${manager}: would install ${pkgs[*]}"
        return 0
    fi

    local install_cmd
    case "$manager" in
        pacman) install_cmd=(sudo pacman -S --needed --noconfirm) ;;
        yay)    install_cmd=(yay -S --needed --noconfirm) ;;
        *)
            error "Unknown package manager: $manager"
            return 1
            ;;
    esac

    if "${install_cmd[@]}" "${pkgs[@]}"; then
        return 0
    fi

    warn "Batch install via ${manager} failed; falling back to package-by-package..."
    local pkg
    for pkg in "${pkgs[@]}"; do
        if ! "${install_cmd[@]}" "$pkg"; then
            error "Failed to install: $pkg"
            FAILED_PKGS+=("$pkg")
        fi
    done
}

# run_group <group>
#
# Looks up the pkgs_<group> array, honors --only/--skip, and installs it with
# the right package manager (yay for the "aur" group, pacman otherwise).
run_group() {
    local group="$1"
    local -n arr="pkgs_${group}"

    if ! group_enabled "$group"; then
        info "Group '$group' skipped by --only/--skip."
        return 0
    fi

    if [[ ${#arr[@]} -eq 0 ]]; then
        return 0
    fi

    local manager="pacman"
    if [[ "$group" == "aur" ]]; then
        manager="yay"
        check_yay
    fi

    info "[$group] packages: ${arr[*]}"
    install_pkgs "pkgs_${group}" "$manager"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

parse_args "$@"
setup_logging

cat <<'EOF'
Welcome to my personal Arch Linux configuration!

This script will install several packages and programs that are
used by me in my routine as a software engineering student and
developer. Some may not be useful to you, so feel free to fork
the repository and make your own customization.
EOF

check_arch
check_repo
check_not_root
check_internet
check_pacman
check_sudo
start_sudo_keepalive
check_disk_space

system_upgrade

# ---------------------------------------------------------------------------
# Package groups
#
# Each array is installed by run_group() as its own group, in GROUP_ORDER.
# Package names were checked against the official repos with
# `pacman -Ssq '^name$'` and against the AUR RPC API; every name below exists
# at the time this was written.
# ---------------------------------------------------------------------------

# Core Sway session: compositor, bar, launcher, terminal, screenshots, clipboard.
pkgs_base=(
    base-devel          # build tooling required to compile AUR packages (makepkg)
    sway swaybg swayidle swaylock
    waybar wofi foot
    wl-clipboard cliphist  # clipboard manager + history for Wayland
    grim slurp              # screenshot capture + region selector for wlroots compositors
    xdg-user-dirs             # creates ~/Downloads, ~/Documents, ~/Pictures etc.; xdg-user-dirs-update (Prompt 3) depends on it
)

# Machine-specific drivers/microcode/firmware (see relato.txt).
pkgs_hardware=(
    intel-ucode          # CPU microcode for Comet Lake
    sof-firmware          # SOF DSP firmware -- audio does not work at all without it
    alsa-ucm-conf           # ALSA Use Case Manager profiles; routes Speaker/Mic1 correctly for this codec
    vulkan-intel              # Vulkan ICD for Intel UHD Graphics (CometLake-U GT2)
    intel-media-driver          # VA-API (iHD) driver for hardware video decode/encode
    fwupd                         # firmware update daemon (BIOS/EC updates via LVFS)
)

# Wayland session plumbing: X11 compat, portals, auth agent, keyring, notifications.
pkgs_session=(
    xorg-xwayland          # lets X11-only apps run inside the Sway session
    xdg-desktop-portal
    xdg-desktop-portal-wlr   # screencast/screenshot portal backend for wlroots compositors
    xdg-desktop-portal-gtk    # file-picker etc. backend -- this is what browsers actually call
    polkit-gnome                # polkit authentication agent; none runs today, so graphical sudo prompts silently fail
    gnome-keyring                 # secret storage: browser passwords, SSH/GPG agent integration
    mako                             # notification daemon; none runs today, so no low-battery/download-done popups. De facto standard for Sway. Prompt 4 adds its exec to the Sway config.
)

# Full PipeWire stack plus diagnostics and a volume control GUI.
pkgs_audio=(
    pipewire pipewire-pulse pipewire-alsa pipewire-jack  # native + PulseAudio-compat + ALSA-compat + JACK-compat
    wireplumber   # session/policy manager for PipeWire
    alsa-utils      # aplay/amixer, useful for diagnosing the SOF setup
    pavucontrol       # GUI volume/routing control
)

# Wi-Fi already works out of the box; this group covers what doesn't: Bluetooth.
pkgs_network=(
    networkmanager   # already active; listed for idempotency/completeness
    bluez bluez-utils  # Bluetooth stack + bluetoothctl -- radio exists but nothing is installed today
    blueman              # GUI Bluetooth manager
)

# Latin + CJK + emoji coverage, a Nerd Font, and Microsoft-metric-compatible fonts.
pkgs_fonts=(
    noto-fonts noto-fonts-emoji noto-fonts-cjk
    ttf-jetbrains-mono-nerd  # Waybar's config depends on a Nerd Font for its icons
    ttf-liberation             # metric-compatible with Arial/Times New Roman/Courier New
)

# GTK/Qt look-and-feel consistency across toolkits.
pkgs_theme=(
    papirus-icon-theme
    nwg-look       # GTK/icon/cursor settings GUI for wlroots compositors
    qt5ct qt6ct       # bridge GTK theme settings into Qt apps under Wayland
)

# File manager, thumbnails, automount, and cross-OS filesystem read support
# (this machine is triple boot: Windows/NTFS + Arch/ext4 + macOS/APFS).
pkgs_files=(
    thunar tumbler     # file manager + thumbnailer
    gvfs gvfs-mtp         # virtual filesystem backends; gvfs-mtp specifically for phone access
    udisks2 udiskie          # automount daemon for removable devices
    ntfs-3g                     # read/write for the Windows partitions
    exfatprogs                     # exFAT, common on external drives/SD cards
    # APFS read support (the macOS partition) has no official-repo package;
    # see pkgs_aur's apfs-fuse-git.
)

# At least one app per common file type; Firefox as a backup browser since
# Zen (AUR, pkgs_aur) can break on update. Programming editor is VS Code
# (pkgs_aur), not duplicated here.
pkgs_apps=(
    zathura zathura-pdf-mupdf  # PDF
    imv                           # image viewer (Wayland-native)
    mpv                             # video and audio playback
    xarchiver zip unzip p7zip         # compressed archives: GUI + CLI backends
    libreoffice-fresh                   # office documents
    firefox                               # backup browser
)

# Extra GStreamer plugins for apps that don't use PipeWire/mpv directly.
pkgs_codecs=(
    gst-plugins-good     # broad codec/format plugin set (e.g. Thunar/tumbler video thumbnails)
    gst-plugin-pipewire    # lets GStreamer apps output straight to PipeWire
)

# Local network printing.
pkgs_printing=(
    cups
    nss-mdns  # resolves .local mDNS hostnames via avahi, needed to discover network printers
)

# TLP only (never together with power-profiles-daemon -- see check in Prompt 4).
pkgs_power=(
    tlp            # battery charge will be capped at 80% in Prompt 3 -- health is already ~82%
    thermald
    brightnessctl
)

# Modern CLI tools, containers, generic runtimes, and dotfiles tooling.
pkgs_dev=(
    git                    # base-devel does not pull this in, but check_yay depends on it
    ripgrep fd bat eza fzf   # modern replacements for grep/find/cat/ls, plus a fuzzy finder
    docker docker-compose
    nodejs npm python jdk-openjdk  # jdk-openjdk: needed by Android/Gradle-based toolchains
    stow                              # dotfiles management (Prompt 5)
)

# AUR packages, installed via yay.
pkgs_aur=(
    zen-browser-bin
    visual-studio-code-bin
    apfs-fuse-git  # read-only FUSE driver for the macOS APFS partition -- no
                   # official-repo APFS support exists; deliberately not the
                   # write-capable linux-apfs-rw-dkms-git, to avoid risking
                   # the macOS filesystem
)

GROUP_ORDER=(
    base hardware session audio network fonts theme files
    apps codecs printing power dev aur
)

for group in "${GROUP_ORDER[@]}"; do
    run_group "$group"
done

if [[ ${#FAILED_PKGS[@]} -gt 0 ]]; then
    warn "The following packages were not installed:"
    printf '  - %s\n' "${FAILED_PKGS[@]}"
else
    success "All packages were installed successfully."
fi
