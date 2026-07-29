#!/usr/bin/env bash

set -e

RED='\033[0;31m'; NC='\033[0m'
error() { echo -e "${RED}[✗]$1${NC}"; }

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

check_internet() {
    if ! ping -c 1 1.1.1.1 &> /dev/null; then
        error "No internet connection."
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

check_disk_space() {
    local min_gb=5
    local avail_kb
    avail_kb=$(df --output=avail / | tail -1)
    local avail_gb=$((avail_kb / 1024 / 1024))

    if [[ $avail_gb -lt $min_gb ]]; then
        error "Not enough disk space (available: ${avail_gb}GB, required: ${min_gb}GB)."
        exit 1
    fi
}

check_yay() {
    if ! command -v yay >/dev/null 2>&1; then
	git clone https://aur.archlinux.org/yay.git
	cd yay
	makepkg -si
	cd ../
	rm -rf yay
    fi
}

check_arch
check_not_root
check_internet
check_pacman
check_sudo
check_disk_space

pkgs=(
    base-devel 
    sway swaybg swayidle swaylock
    waybar wofi foot
    pipewire pipewire-pulse wireplumber
    xdg-desktop-portal-wlr
    wl-clipboard cliphist
    grim slurp
    nwg-look papirus-icon-theme
    polkit-gnome
)

pkgs_yay=(
    zen-browser-bin
    visual-studio-code-bin
)

cat <<'EOF'
Welcome to my personal Arch Linux configuration!

This script will install several packages and programs that are
used by me in my routine as a software engineering student and
developer. Some may not be useful to you, so feel free to fork
the repository and make your own customiza

This are the programs and packeges that will be installed:
EOF
echo ${pkgs[@]}

sudo pacman -S --needed --noconfirm "${pkgs[@]}"

check_yay

yay -S --noconfirm "${pkgs_yay[@]}"
