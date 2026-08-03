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
DOCTOR=false
RUN_DOTFILES=false
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
  --dotfiles             Also apply the repo's dotfiles with GNU Stow (runs dotfiles.sh).
  --doctor               Diagnostics only: check the system and report OK/WARN/FAIL per
                         item, changing nothing. Exits non-zero if anything FAILs.
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
            --dotfiles) RUN_DOTFILES=true ;;
            --doctor) DOCTOR=true ;;
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

    [[ "$default" == "y" ]] && hint="[Y/n]" || hint="[y/N]"

    if $ASSUME_YES; then
        reply="$default"
    elif [[ -t 0 ]]; then
        read -r -p "$prompt $hint " reply
        reply="${reply:-$default}"
    else
        warn "No interactive terminal to ask \"$prompt\" -- using the default (${default})."
        reply="$default"
    fi

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

# A single network blip used to abort the whole run (a 30-minute install is
# a long time to lose to one dropped packet), so retry up to 3 times with a
# growing wait: 2s after the first failure, 4s after the second.
check_internet() {
    local attempt delay=2

    for attempt in 1 2 3; do
        if curl -fsS --max-time 5 -o /dev/null "https://archlinux.org"; then
            return 0
        fi

        if [[ $attempt -lt 3 ]]; then
            warn "Could not reach https://archlinux.org (attempt ${attempt}/3), retrying in ${delay}s..."
            sleep "$delay"
            delay=$((delay * 2))
        fi
    done

    error "No internet connection (failed to reach https://archlinux.org after 3 attempts)."
    exit 1
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
    kanshi gammastep             # output/display layout profiles + auto color temperature; execs added in Prompt 4's sway-exec-snippet.conf
)

# Machine-specific drivers/microcode/firmware (see relato.txt).
pkgs_hardware=(
    intel-ucode          # CPU microcode for Comet Lake
    sof-firmware          # SOF DSP firmware -- audio does not work at all without it
    alsa-ucm-conf           # ALSA Use Case Manager profiles; routes Speaker/Mic1 correctly for this codec
    vulkan-intel              # Vulkan ICD for Intel UHD Graphics (CometLake-U GT2)
    intel-media-driver          # VA-API (iHD) driver for hardware video decode/encode
    libva-utils                   # vainfo -- lets --doctor verify VA-API acceleration works
    fwupd                           # firmware update daemon (BIOS/EC updates via LVFS)
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
    playerctl           # media keys (XF86AudioNext/Prev/Play) in the sway config
)

# Wi-Fi already works out of the box; this group covers what doesn't:
# Bluetooth, a firewall, and the tray applets Prompt 4's exec snippet needs.
pkgs_network=(
    networkmanager network-manager-applet  # already active; applet gives a tray icon (nm-applet)
    bluez bluez-utils  # Bluetooth stack + bluetoothctl -- radio exists but nothing is installed today
    blueman              # GUI Bluetooth manager + tray applet (blueman-applet)
    ufw                     # firewall; Prompt 4 enables ufw.service (rules/policy are not configured here)
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
    evince                     # PDF
    gpu-screen-recorder        # screen recording (F10 keybind / record.sh in the sway dotfiles)
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
    avahi      # was already present at audit time, but not declared anywhere -- needed for
               # avahi-daemon.service (Prompt 4) and for nss-mdns to have anything to talk to
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
    pacman-contrib                       # provides paccache, needed for paccache.timer (Prompt 4)
)

# AUR packages, installed via yay.
pkgs_aur=(
    zen-browser-bin
    visual-studio-code-bin
    bibata-cursor-theme-bin  # cursor theme referenced by the GTK dotfiles (Bibata-Modern-Classic)
    apfs-fuse-git  # read-only FUSE driver for the macOS APFS partition -- no
                   # official-repo APFS support exists; deliberately not the
                   # write-capable linux-apfs-rw-dkms-git, to avoid risking
                   # the macOS filesystem
)

# NOT alphabetical/arbitrary: "audio" must install before "base". waybar (in
# "base") pulls in a virtual "jack" provider dependency; under --noconfirm,
# pacman would resolve that implicitly to whatever provider it defaults to
# before "audio" gets a chance to explicitly install pipewire-jack -- risking
# jack2 landing on a clean install and an unrecoverable conflict in
# non-interactive mode. Installing "audio" first satisfies that dependency
# with the right provider up front.
GROUP_ORDER=(
    audio base hardware session network fonts theme files
    apps codecs printing power dev aur
)

# ---------------------------------------------------------------------------
# System configuration (Prompt 3) -- runs once packages are installed.
#
# Every step here must be idempotent: running install.sh twice must not
# duplicate a line or clobber hand-made customization. Any /etc file edited
# in place goes through backup_etc_file() first. /etc/fstab, /boot, and
# anything bootloader-related are never touched here.
# ---------------------------------------------------------------------------

# backup_etc_file <file>
#
# Copies <file> to <file>.bak-YYYYMMDD if it exists and hasn't already been
# backed up today (so re-running the script the same day doesn't overwrite
# the pre-install snapshot with an already-modified version).
backup_etc_file() {
    local file="$1"

    [[ -f "$file" ]] || return 0

    local backup="${file}.bak-$(date +%Y%m%d)"
    [[ -e "$backup" ]] && return 0

    if $DRY_RUN; then
        info "[dry-run] would back up $file to $backup"
        return 0
    fi

    sudo cp -a "$file" "$backup"
}

# 1. Keyboard -- this machine has an ABNT2 keyboard, but there is no console
# (kbd) keymap for this ThinkPad's known ABNT2 quirk (the "/" and "?" key
# reports a different scancode than a regular ABNT2 keyboard). The available
# console keymaps are only br-abnt, br-abnt2, br-latin1-abnt2, br-latin1-us
# -- none ThinkPad-aware. The fix only exists at the XKB level: `localectl
# list-x11-keymap-variants br` lists "thinkpad" and "thinkpad_nodeadkeys".
# So: the TTY keymap is deliberately left as "us" (untouched), and the
# br/thinkpad layout is applied only inside the Sway (Wayland) session, via
# a snippet to review and paste in yourself -- same pattern as Prompt 4's
# exec snippet, since this repo doesn't own your actual Sway config.
config_keyboard() {
    local file="$SCRIPT_DIR/sway-keyboard-snippet.conf"

    if $DRY_RUN; then
        info "[dry-run] would write $file (Sway XKB config: br/thinkpad)"
        return 0
    fi

    cat > "$file" <<'EOF'
# Paste into your Sway config (e.g. dotfiles/sway/.config/sway/config).
#
# The console (TTY) keymap is deliberately left as "us": there is no
# console (kbd) keymap that accounts for this ThinkPad's ABNT2 quirk ("/"
# and "?" end up wrong/missing), and forcing br-abnt2 there is known to
# break exactly those two keys on this hardware. The "thinkpad" XKB
# variant (confirmed available via `localectl list-x11-keymap-variants
# br`) fixes it at the Wayland/XKB level instead. Use
# xkb_variant thinkpad_nodeadkeys if you'd rather not have dead keys for
# accents.
input type:keyboard {
    xkb_layout br
    xkb_variant thinkpad
}
EOF

    success "Wrote $file -- paste it into your Sway config. Console (TTY) keymap left as 'us'."
}

# 2. Wayland environment variables -- read by the systemd user manager via
# pam_systemd at login, i.e. before Sway starts from the TTY, not just inside
# the running session. XDG_CURRENT_DESKTOP is what makes the XDG portals pick
# the right backend (it's empty today).
config_wayland_env() {
    local dir="$HOME/.config/environment.d"
    local file="$dir/10-wayland-native.conf"

    if $DRY_RUN; then
        info "[dry-run] would write $file (native Wayland env vars + XDG_CURRENT_DESKTOP=sway)"
        return 0
    fi

    mkdir -p "$dir"
    cat > "$file" <<'EOF'
# Managed by install.sh -- native Wayland for Firefox/Zen, Qt, Electron, SDL,
# and the standard Java AWT/Swing fix for tiling window managers.
MOZ_ENABLE_WAYLAND=1
QT_QPA_PLATFORM=wayland
ELECTRON_OZONE_PLATFORM_HINT=wayland
SDL_VIDEODRIVER=wayland
_JAVA_AWT_WM_NONREPARENTING=1
XDG_CURRENT_DESKTOP=sway
EOF

    success "Wrote $file."
}

# 3. Portal backend selection -- GTK backend doesn't implement ScreenCast or
# Screenshot for wlroots compositors, only the wlr backend does; everything
# else (notably the file picker) goes through gtk.
config_portals() {
    local dir="$HOME/.config/xdg-desktop-portal"
    local file="$dir/sway-portals.conf"

    if $DRY_RUN; then
        info "[dry-run] would write $file (screencast/screenshot via wlr, everything else via gtk)"
        return 0
    fi

    mkdir -p "$dir"
    cat > "$file" <<'EOF'
[preferred]
default=gtk
org.freedesktop.impl.portal.ScreenCast=wlr
org.freedesktop.impl.portal.Screenshot=wlr
EOF

    success "Wrote $file."
}

# 4. mDNS hostname resolution -- needed to discover network printers via
# avahi/CUPS. Inserted right before the "files" token if present, otherwise
# appended to the hosts line; never duplicated on re-runs.
config_nsswitch() {
    local file="/etc/nsswitch.conf"

    if grep -qE "^hosts:.*mdns_minimal" "$file" 2>/dev/null; then
        return 0
    fi

    if $DRY_RUN; then
        info "[dry-run] would add mdns_minimal to the hosts line in $file"
        return 0
    fi

    backup_etc_file "$file"

    if grep -qE '^hosts:.*\bfiles\b' "$file"; then
        sudo sed -i -E '/^hosts:/ s/\bfiles\b/mdns_minimal [NOTFOUND=return] files/' "$file"
    else
        sudo sed -i -E '/^hosts:/ s/$/ mdns_minimal [NOTFOUND=return]/' "$file"
    fi

    success "Added mdns_minimal to the hosts line in $file."
}

# 5. User groups -- video/input for the session, docker only if it actually
# got installed. Only touches the account if something is actually missing,
# so the "log out" warning doesn't nag on every run.
config_user_groups() {
    local want=(video input) g current missing=()

    if command -v docker >/dev/null 2>&1; then
        want+=(docker)
    fi

    # `id -un` rather than $USER: the variable is set by login shells and PAM,
    # but not by every context this can run from (docker exec, su -c, cron),
    # and an unbound $USER aborts the whole script under `set -u`.
    local user
    user="$(id -un)"

    current=" $(id -nG "$user") "
    for g in "${want[@]}"; do
        [[ "$current" == *" $g "* ]] || missing+=("$g")
    done

    [[ ${#missing[@]} -eq 0 ]] && return 0

    if $DRY_RUN; then
        info "[dry-run] would add $user to groups: ${missing[*]}"
        return 0
    fi

    sudo usermod -aG "$(IFS=,; echo "${missing[*]}")" "$user"
    warn "Added $user to groups: ${missing[*]}. Log out and back in for this to take effect."
}

# 6. Standard XDG user directories (~/Downloads, ~/Documents, ~/Pictures, ...).
config_xdg_user_dirs() {
    if ! command -v xdg-user-dirs-update >/dev/null 2>&1; then
        warn "xdg-user-dirs-update not found (xdg-user-dirs package missing?) -- skipping."
        return 0
    fi

    if $DRY_RUN; then
        info "[dry-run] would run xdg-user-dirs-update"
        return 0
    fi

    xdg-user-dirs-update
    success "Standard home directories created/updated."
}

# 7. Default applications -- today almost everything either opens in the
# browser or has no handler at all. Only takes over a MIME type if it's
# currently unset or pointing at whatever the browser currently is, so any
# deliberate hand-made choice is left alone. "The browser" is resolved live
# via the current https handler rather than hardcoded to zen.desktop/
# firefox.desktop, since that default can legitimately change over time.
ensure_mime_default() {
    local mime="$1" desktop="$2" browser="${3:-}" current
    current="$(xdg-mime query default "$mime" 2>/dev/null || true)"

    if [[ -n "$current" && "$current" != "$browser" ]]; then
        return 0
    fi

    if $DRY_RUN; then
        info "[dry-run] would set default handler for $mime to $desktop"
        return 0
    fi

    xdg-mime default "$desktop" "$mime"
}

config_default_apps() {
    if ! command -v xdg-mime >/dev/null 2>&1; then
        warn "xdg-mime not found -- skipping default application setup."
        return 0
    fi

    local browser
    browser="$(xdg-mime query default x-scheme-handler/https 2>/dev/null || true)"

    ensure_mime_default "application/pdf" "org.gnome.Evince.desktop" "$browser"
    ensure_mime_default "image/png" "imv.desktop" "$browser"
    ensure_mime_default "image/jpeg" "imv.desktop" "$browser"
    ensure_mime_default "video/mp4" "mpv.desktop" "$browser"
    ensure_mime_default "audio/mpeg" "mpv.desktop" "$browser"
    ensure_mime_default "text/plain" "code.desktop" "$browser"
    ensure_mime_default "inode/directory" "thunar.desktop" "$browser"
    ensure_mime_default "application/zip" "xarchiver.desktop" "$browser"

    # http/https: never overridden if something is already set (whatever
    # that is IS the intended browser); only filled in if totally unset.
    ensure_mime_default "x-scheme-handler/http" "${browser:-zen.desktop}" ""
    ensure_mime_default "x-scheme-handler/https" "${browser:-zen.desktop}" ""

    success "Default applications configured for common MIME types."
}

# 8. pacman.conf niceties -- Color/ParallelDownloads/VerbosePkgLists are safe
# to just turn on; multilib changes what repos are available, so ask first.
config_pacman_conf() {
    local file="/etc/pacman.conf"
    local already_ok=true

    grep -qE '^Color$' "$file" || already_ok=false
    grep -qE '^ParallelDownloads' "$file" || already_ok=false
    grep -qE '^VerbosePkgLists$' "$file" || already_ok=false

    if ! $already_ok; then
        if $DRY_RUN; then
            info "[dry-run] would enable Color/ParallelDownloads/VerbosePkgLists in $file"
        else
            backup_etc_file "$file"
            sudo sed -i \
                -e 's/^#Color$/Color/' \
                -e 's/^#ParallelDownloads/ParallelDownloads/' \
                -e 's/^#VerbosePkgLists$/VerbosePkgLists/' \
                "$file"
            success "Enabled Color, ParallelDownloads and VerbosePkgLists in $file."
        fi
    fi

    if grep -qE '^\[multilib\]$' "$file" 2>/dev/null; then
        return 0
    fi

    if ! confirm "Enable the [multilib] repository in $file (32-bit libraries, e.g. Wine/Steam)?" "n"; then
        info "multilib left disabled."
        return 0
    fi

    if $DRY_RUN; then
        info "[dry-run] would enable [multilib] in $file"
        return 0
    fi

    backup_etc_file "$file"
    sudo sed -i '/^#\[multilib\]$/,+1 s/^#//' "$file"
    success "Enabled [multilib] in $file (run 'sudo pacman -Sy' before installing from it)."
}

# 9. Cap battery charging at 80% via TLP -- health is already at ~82% of
# design capacity. Uses a dedicated drop-in instead of editing the (not yet
# installed) main tlp.conf, so this is a plain idempotent overwrite.
config_battery_limit() {
    local dir="/etc/tlp.d"
    local file="$dir/battery-charge-limit.conf"

    if grep -q "^STOP_CHARGE_THRESH_BAT0=80$" "$file" 2>/dev/null; then
        return 0
    fi

    if $DRY_RUN; then
        info "[dry-run] would write $file (cap battery charge at 80%)"
        return 0
    fi

    sudo mkdir -p "$dir"
    sudo tee "$file" >/dev/null <<'EOF'
# Managed by install.sh -- battery health is already at ~82%, cap charging
# at 80% to slow further degradation.
STOP_CHARGE_THRESH_BAT0=80
EOF

    success "Capped battery charge at 80% in $file (takes effect once tlp is enabled, see Prompt 4)."
}

run_system_config() {
    config_keyboard
    config_wayland_env
    config_portals
    config_nsswitch
    config_user_groups
    config_xdg_user_dirs
    config_default_apps
    config_pacman_conf
    config_battery_limit
}

# ---------------------------------------------------------------------------
# Service enabling (Prompt 4) -- runs last, after packages and configuration.
#
# Every enable_* helper only acts on a service whose providing package is
# actually installed. That's checked with `pacman -Qq`, the ground truth,
# rather than only install_pkgs' FAILED_PKGS: FAILED_PKGS is empty on a
# second run where nothing needed (re)installing, so it can't by itself
# prove a package IS installed, only that it didn't fail THIS run. Already
# enabled-and-active services are left alone, so re-running is a no-op.
# ---------------------------------------------------------------------------

# enable_service <unit> [pkg]
#
# Enables and starts a systemd service/timer/socket, but only if its
# providing package is actually installed; skips (doesn't fail) otherwise.
enable_service() {
    local unit="$1" pkg="${2:-}"

    if [[ -n "$pkg" ]] && ! pacman -Qq "$pkg" &>/dev/null; then
        warn "Skipping $unit: package '$pkg' is not installed."
        return 0
    fi

    if systemctl is-enabled --quiet "$unit" 2>/dev/null && systemctl is-active --quiet "$unit"; then
        return 0
    fi

    if $DRY_RUN; then
        info "[dry-run] would enable --now $unit"
        return 0
    fi

    sudo systemctl enable --now "$unit"
    success "Enabled $unit."
}

# TLP vs power-profiles-daemon conflict (CLAUDE.md rule 5): if PPD is
# already active, refuse to also enable TLP instead of enabling both.
enable_tlp_service() {
    if ! pacman -Qq tlp &>/dev/null; then
        return 0
    fi

    if systemctl is-active --quiet power-profiles-daemon.service; then
        error "power-profiles-daemon.service is active -- refusing to also enable tlp.service (they conflict). Disable power-profiles-daemon first if you want TLP instead."
        return 0
    fi

    enable_service tlp.service tlp
}

# Docker's group grants root-equivalent access to whoever is in it -- ask
# before enabling the service, even though the package is already installed.
enable_docker_service() {
    if ! pacman -Qq docker &>/dev/null; then
        return 0
    fi

    if systemctl is-enabled --quiet docker.service 2>/dev/null && systemctl is-active --quiet docker.service; then
        return 0
    fi

    if ! confirm "Enable and start docker.service now?" "n"; then
        info "docker.service left disabled."
        return 0
    fi

    if $DRY_RUN; then
        info "[dry-run] would enable --now docker.service"
        return 0
    fi

    sudo systemctl enable --now docker.service
    success "Enabled docker.service."
}

# PipeWire runs as user (not system) services -- only report on them here,
# never alter them.
check_pipewire_user_services() {
    local units=(pipewire.service pipewire-pulse.service wireplumber.service) u

    for u in "${units[@]}"; do
        if systemctl --user is-active --quiet "$u" 2>/dev/null; then
            success "User service $u is active."
        else
            warn "User service $u is not active."
        fi
    done
}

# Sway doesn't start any of these daemons on its own. Written to a separate
# file instead of editing the actual Sway config directly, so it can be
# reviewed and pasted in by hand.
generate_sway_exec_snippet() {
    local file="$SCRIPT_DIR/sway-exec-snippet.conf"

    if $DRY_RUN; then
        info "[dry-run] would write $file (exec lines for daemons that don't start on their own)"
        return 0
    fi

    cat > "$file" <<'EOF'
# Paste into your Sway config (e.g. dotfiles/sway/.config/sway/config).
# None of these start on their own -- nothing execs them today.

# Polkit authentication agent (graphical sudo/auth prompts).
exec /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1

# Notification daemon.
exec mako

# Automount for removable devices (USB drives, SD cards).
exec udiskie --tray

# Network and Bluetooth tray applets (network-manager-applet and blueman,
# both in pkgs_network).
exec nm-applet --indicator
exec blueman-applet

# Clipboard history, persisted via cliphist (wl-clipboard/cliphist already
# installed).
exec wl-paste --type text --watch cliphist store
exec wl-paste --type image --watch cliphist store

# Output/display layout profiles (e.g. auto-switching when a monitor is
# plugged in).
exec kanshi

# Automatic color temperature by time of day.
exec gammastep
EOF

    success "Wrote $file -- paste into your Sway config."
}

run_enable_services() {
    enable_service NetworkManager.service networkmanager
    enable_service bluetooth.service bluez
    enable_service cups.socket cups
    enable_service avahi-daemon.service avahi
    enable_tlp_service
    enable_service thermald.service thermald
    enable_service fstrim.timer
    enable_service ufw.service ufw
    enable_service paccache.timer pacman-contrib
    enable_docker_service
    check_pipewire_user_services
    generate_sway_exec_snippet
}

# ---------------------------------------------------------------------------
# Doctor mode (Prompt 6) -- read-only diagnostics. Installs nothing, changes
# nothing; reports each item as OK / WARN / FAIL with a fix suggestion, and
# exits non-zero if anything FAILs (usable in CI).
# ---------------------------------------------------------------------------

DOC_OK=0; DOC_WARN=0; DOC_FAIL=0

doc_ok()   { echo -e "  ${GREEN}[OK]  ${NC} $1"; DOC_OK=$((DOC_OK + 1)); }
doc_warn() {
    echo -e "  ${YELLOW}[WARN]${NC} $1"
    [[ -n "${2:-}" ]] && echo -e "         ${YELLOW}fix:${NC} $2"
    DOC_WARN=$((DOC_WARN + 1))
}
doc_fail() {
    echo -e "  ${RED}[FAIL]${NC} $1"
    [[ -n "${2:-}" ]] && echo -e "         ${RED}fix:${NC} $2"
    DOC_FAIL=$((DOC_FAIL + 1))
}

doctor_audio() {
    info "Audio"

    if grep -qE '^ *[0-9]+ \[' /proc/asound/cards 2>/dev/null; then
        doc_ok "ALSA card registered in /proc/asound/cards"
    else
        doc_fail "No ALSA card registered" \
            "check that sof-firmware is installed, then reboot; inspect 'sudo dmesg | grep -i sof'"
    fi

    if command -v pactl >/dev/null 2>&1; then
        if pactl list short sinks 2>/dev/null | grep -qv auto_null; then
            doc_ok "PipeWire exposes a real sink (not auto_null)"
        else
            doc_fail "No real audio sink (auto_null only, or none)" \
                "install sof-firmware and alsa-ucm-conf, then reboot"
        fi
    else
        doc_warn "pactl not available, cannot inspect sinks" \
            "install pipewire-pulse (pulls in libpulse)"
    fi

    if find /usr/lib/firmware/intel/sof* -name 'sof-cml*' 2>/dev/null | grep -q .; then
        doc_ok "SOF firmware for Comet Lake (sof-cml*) present on disk"
    else
        doc_fail "SOF firmware sof-cml* missing under /usr/lib/firmware" "install sof-firmware"
    fi
}

doctor_session() {
    info "Session"

    if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
        doc_ok "Session type is wayland"
    else
        doc_fail "XDG_SESSION_TYPE is '${XDG_SESSION_TYPE:-<empty>}', expected 'wayland'" \
            "run --doctor from inside the Sway session"
    fi

    if [[ -n "${DISPLAY:-}" ]]; then
        doc_ok "DISPLAY is set (XWayland active)"
    else
        doc_fail "DISPLAY is empty -- XWayland is not running, X11-only apps won't open" \
            "install xorg-xwayland and restart Sway"
    fi

    if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
        doc_ok "XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP}"
    else
        doc_fail "XDG_CURRENT_DESKTOP is empty -- portals can't pick the right backend" \
            "apply the environment.d config step and log in again"
    fi
}

doctor_portals() {
    info "XDG portals"

    if ! command -v busctl >/dev/null 2>&1; then
        doc_warn "busctl not available, cannot inspect the session bus"
        return 0
    fi

    local bus
    bus="$(busctl --user list --no-pager 2>/dev/null || true)"

    if grep -q 'org.freedesktop.impl.portal.desktop.gtk' <<<"$bus"; then
        doc_ok "GTK portal backend is on the bus (browser file picker works)"
    else
        doc_fail "GTK portal backend is NOT on the bus, only wlr at best" \
            "install xdg-desktop-portal-gtk and make sure XDG_CURRENT_DESKTOP is set"
    fi

    if grep -q 'org.freedesktop.impl.portal.desktop.wlr' <<<"$bus"; then
        doc_ok "wlr portal backend is on the bus (screencast/screenshot works)"
    else
        doc_warn "wlr portal backend is not on the bus" "install xdg-desktop-portal-wlr"
    fi
}

doctor_processes() {
    info "Session daemons"

    if pgrep -f 'polkit-gnome-authentication-agent|polkit-kde-auth|lxpolkit|polkit-mate' >/dev/null; then
        doc_ok "polkit authentication agent is running"
    else
        doc_fail "No polkit agent running -- graphical privilege prompts will silently fail" \
            "paste the polkit-gnome exec from sway-exec-snippet.conf into your Sway config"
    fi

    if pgrep -x mako >/dev/null || pgrep -x dunst >/dev/null; then
        doc_ok "Notification daemon is running"
    else
        doc_fail "No notification daemon running -- notifications go nowhere" \
            "paste the mako exec from sway-exec-snippet.conf into your Sway config"
    fi
}

doctor_fonts() {
    info "Fonts"

    if ! command -v fc-match >/dev/null 2>&1; then
        doc_warn "fc-match not available" "install fontconfig"
        return 0
    fi

    local family
    family="$(fc-match -f '%{family}' emoji 2>/dev/null || true)"
    if grep -qi 'emoji' <<<"$family"; then
        doc_ok "emoji resolves to a real emoji font: $family"
    else
        doc_fail "emoji resolves to '$family' -- a generic fallback, emoji will render broken" \
            "install noto-fonts-emoji and run 'fc-cache -f'"
    fi

    family="$(fc-match -f '%{family}' monospace 2>/dev/null || true)"
    if grep -qi 'nerd' <<<"$family"; then
        doc_ok "monospace resolves to the expected Nerd Font: $family"
    else
        doc_warn "monospace resolves to '$family', not a Nerd Font -- Waybar icons will break" \
            "install ttf-jetbrains-mono-nerd and run 'fc-cache -f'"
    fi
}

doctor_default_apps() {
    info "Default applications"

    if ! command -v xdg-mime >/dev/null 2>&1; then
        doc_warn "xdg-mime not available" "install xdg-utils"
        return 0
    fi

    local mime missing=()
    for mime in application/pdf image/png image/jpeg video/mp4 audio/mpeg \
                text/plain inode/directory application/zip \
                x-scheme-handler/http x-scheme-handler/https; do
        if [[ -z "$(xdg-mime query default "$mime" 2>/dev/null)" ]]; then
            missing+=("$mime")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        doc_ok "Every main MIME type has a default handler"
    else
        doc_fail "MIME types without a default handler: ${missing[*]}" \
            "run the config step (install.sh --only=config)"
    fi
}

doctor_video() {
    info "Video acceleration"

    if ! command -v vainfo >/dev/null 2>&1; then
        doc_warn "vainfo not installed, cannot verify VA-API" "install libva-utils"
        return 0
    fi

    local profiles
    profiles="$(vainfo 2>/dev/null | grep -c 'VAProfile' || true)"
    if [[ "$profiles" -gt 0 ]]; then
        doc_ok "VA-API reports $profiles acceleration profiles"
    else
        doc_fail "vainfo reports no acceleration profiles" "install intel-media-driver"
    fi
}

doctor_power() {
    info "Power management"

    local active=()
    systemctl is-active --quiet tlp.service 2>/dev/null && active+=(tlp)
    systemctl is-active --quiet power-profiles-daemon.service 2>/dev/null && active+=(power-profiles-daemon)

    case ${#active[@]} in
        1) doc_ok "Exactly one power manager active: ${active[0]}" ;;
        0) doc_warn "No power manager active" "enable TLP via the services step" ;;
        *) doc_fail "CONFLICT: tlp AND power-profiles-daemon are both active" \
               "sudo systemctl disable --now power-profiles-daemon" ;;
    esac
}

doctor_health() {
    info "System health"

    local failed
    failed="$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | tr '\n' ' ')"
    if [[ -z "${failed// /}" ]]; then
        doc_ok "No failed system units"
    else
        doc_fail "Failed system units: $failed" "systemctl status <unit>"
    fi

    failed="$(systemctl --user --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | tr '\n' ' ')"
    if [[ -z "${failed// /}" ]]; then
        doc_ok "No failed user units"
    else
        doc_fail "Failed user units: $failed" "systemctl --user status <unit>"
    fi

    local errors
    if errors="$(journalctl -p 3 -b -q --no-pager 2>/dev/null)"; then
        if [[ -z "$errors" ]]; then
            doc_ok "No priority<=3 errors in the current boot"
        else
            doc_warn "$(grep -c . <<<"$errors") priority<=3 journal errors this boot (ACPI noise is known-harmless on this machine)" \
                "journalctl -p 3 -b"
        fi
    else
        doc_warn "Cannot read the system journal as this user" \
            "add yourself to the systemd-journal group, or run 'sudo journalctl -p 3 -b'"
    fi
}

doctor_packages() {
    info "Declared packages vs installed"

    local group arr_name pkg missing=()
    for group in "${GROUP_ORDER[@]}"; do
        arr_name="pkgs_${group}[@]"
        for pkg in "${!arr_name}"; do
            pacman -Qq "$pkg" >/dev/null 2>&1 || missing+=("$pkg ($group)")
        done
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        doc_ok "Every package declared in the groups is installed"
    else
        doc_fail "${#missing[@]} declared package(s) not installed" "run install.sh"
        printf '         - %s\n' "${missing[@]}"
    fi
}

doctor_dotfiles() {
    info "Dotfiles"

    # Broken symlinks under ~/.config are the classic symptom of the repo
    # (the symlink target) having been moved after stowing. Files named
    # "lock" are excluded: Mozilla-family browsers (Firefox/Zen) implement
    # profile locking as an intentionally dangling symlink to "IP:+PID",
    # which would make this check permanently red while a browser runs.
    local broken=()
    mapfile -t broken < <(find "$HOME/.config" -xtype l ! -name lock 2>/dev/null)
    if [[ ${#broken[@]} -eq 0 ]]; then
        doc_ok "No broken symlinks in ~/.config"
    else
        doc_fail "${#broken[@]} broken symlink(s) in ~/.config -- was the repo moved?" \
            "remove the dead links (or restore the repo path), then run ./dotfiles.sh --restow"
        printf '         - %s\n' "${broken[@]}"
    fi

    # For each stow package that actually has content, every one of its
    # files must reach the repo's dotfiles/ through the filesystem. A file
    # counts as applied if IT is a symlink into dotfiles/ OR any parent
    # directory on its path is one -- stow's "tree folding" links a whole
    # directory (e.g. ~/.config/foot -> dotfiles/foot/.config/foot), leaving
    # the files inside it as real files behind a dir symlink. readlink -f
    # canonicalizes every path component, so one resolution covers both
    # cases. Empty skeleton packages don't count either way.
    local stow_dir="$SCRIPT_DIR/dotfiles"
    local pkg pkg_name rel resolved applied files=() unapplied=()
    local content_pkgs=0

    for pkg in "$stow_dir"/*/; do
        [[ -d "$pkg" ]] || continue
        pkg_name="$(basename "$pkg")"

        mapfile -t files < <(cd "$pkg" && find . \( -type f -o -type l \) | sed 's|^\./||')
        [[ ${#files[@]} -eq 0 ]] && continue
        content_pkgs=$((content_pkgs + 1))

        applied=true
        for rel in "${files[@]}"; do
            resolved="$(readlink -f "$HOME/$rel" 2>/dev/null || true)"
            case "$resolved" in
                "$stow_dir"/*) continue ;;
            esac
            applied=false
            break
        done

        $applied || unapplied+=("$pkg_name")
    done

    if [[ $content_pkgs -eq 0 ]]; then
        doc_ok "dotfiles/ packages are all empty skeletons (nothing to verify yet)"
    elif [[ ${#unapplied[@]} -eq 0 ]]; then
        doc_ok "All $content_pkgs stow package(s) with content are applied in \$HOME"
    else
        doc_warn "Stow package(s) with content but not applied: ${unapplied[*]}" \
            "run ./dotfiles.sh (or ./dotfiles.sh --restow)"
    fi
}

run_doctor() {
    echo
    info "Doctor: read-only diagnostics (nothing will be installed or changed)."
    echo

    doctor_audio
    doctor_session
    doctor_portals
    doctor_processes
    doctor_fonts
    doctor_default_apps
    doctor_video
    doctor_power
    doctor_health
    doctor_packages
    doctor_dotfiles

    echo
    if [[ $DOC_FAIL -gt 0 ]]; then
        error "Doctor: $DOC_OK ok, $DOC_WARN warning(s), $DOC_FAIL failure(s)."
        return 1
    fi
    success "Doctor: $DOC_OK ok, $DOC_WARN warning(s), no failures."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

parse_args "$@"
setup_logging

# Doctor mode: pure diagnostics, no sudo, no installs -- run and exit.
if $DOCTOR; then
    if run_doctor; then
        exit 0
    else
        exit 1
    fi
fi

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

for group in "${GROUP_ORDER[@]}"; do
    run_group "$group"
done

if group_enabled "config"; then
    run_system_config
else
    info "Group 'config' skipped by --only/--skip."
fi

if group_enabled "services"; then
    run_enable_services
else
    info "Group 'services' skipped by --only/--skip."
fi

if $RUN_DOTFILES; then
    if $DRY_RUN; then
        info "[dry-run] would run $SCRIPT_DIR/dotfiles.sh"
    else
        dotfiles_args=()
        $ASSUME_YES && dotfiles_args+=(--yes)
        "$SCRIPT_DIR/dotfiles.sh" "${dotfiles_args[@]}"
    fi
fi

if [[ ${#FAILED_PKGS[@]} -gt 0 ]]; then
    warn "The following packages were not installed:"
    printf '  - %s\n' "${FAILED_PKGS[@]}"
else
    success "All packages were installed successfully."
fi
