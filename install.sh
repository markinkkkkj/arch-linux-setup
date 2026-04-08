#!/usr/bin/env bash
# ============================================================
#  Arch Linux – Hyprland setup script
#  Execute a partir da pasta dotfiles/:  bash install.sh
# ============================================================
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }

# ── Verificações iniciais ────────────────────────────────────
if [[ $EUID -eq 0 ]]; then
    error "Não execute como root. Use um usuário normal com sudo."
    exit 1
fi

info "Iniciando setup do Hyprland..."

# ── 1. Atualizar sistema ─────────────────────────────────────
info "Atualizando sistema..."
sudo pacman -Syu --noconfirm

# ── 2. Configurar bash ──────────────────────────────────────
info "Configurando bash..."
sudo pacman -S --needed --noconfirm bash-completion

cp "$DOTFILES_DIR/bash/.bashrc" ~/.bashrc

if [[ "$SHELL" != "$(which bash)" ]]; then
    info "Definindo bash como shell padrão..."
    chsh -s "$(which bash)"
fi

# ── 3. Instalar dependências base ────────────────────────────
info "Instalando pacotes base..."
sudo pacman -S --needed --noconfirm \
    base-devel git sudo curl wget unzip \
    linux-firmware intel-ucode sof-firmware \
    networkmanager sway \
    pipewire pipewire-alsa pipewire-pulse wireplumber rtkit alsa-utils \
    hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
    waybar \
    kitty \
    rofi \
    numlockx \
    ttf-jetbrains-mono-nerd noto-fonts-emoji \
    pavucontrol \
    imagemagick ffmpegthumbnailer perl-image-exiftool \
    neovim \
    yazi \
    zram-generator \
    efibootmgr \
    nvm

# ── 4. Instalar yay (AUR helper) ─────────────────────────────
if ! command -v yay &>/dev/null; then
    info "Instalando yay..."
    cd /tmp
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd "$DOTFILES_DIR"
else
    info "yay já instalado, pulando."
fi

# ── 5. Instalar pacotes AUR ──────────────────────────────────
info "Instalando pacotes AUR..."
yay -S --needed --noconfirm \
    awww \
    brave-bin

# ── 6. Copiar configs ────────────────────────────────────────
info "Copiando configurações..."

mkdir -p ~/.config/hypr
cp "$DOTFILES_DIR/hypr/hyprland.conf"           ~/.config/hypr/hyprland.conf
cp "$DOTFILES_DIR/hypr/archlinux-wallpaper.png" ~/.config/hypr/archlinux-wallpaper.png

# hyprpaper.conf: substitui o caminho do usuário antigo pelo atual
sed "s|/home/[^/]*/|$HOME/|g" \
    "$DOTFILES_DIR/hypr/hyprpaper.conf" > ~/.config/hypr/hyprpaper.conf

mkdir -p ~/.config/waybar
cp "$DOTFILES_DIR/waybar/config.jsonc" ~/.config/waybar/config.jsonc
cp "$DOTFILES_DIR/waybar/style.css"    ~/.config/waybar/style.css

mkdir -p ~/.config/kitty
cp "$DOTFILES_DIR/kitty/kitty.conf" ~/.config/kitty/kitty.conf

mkdir -p ~/.config/yazi
cp "$DOTFILES_DIR/yazi/yazi.toml"   ~/.config/yazi/yazi.toml
cp "$DOTFILES_DIR/yazi/keymap.toml" ~/.config/yazi/keymap.toml

# atualizar cache de fontes após instalar noto-fonts-emoji
fc-cache -fv &>/dev/null

# ── 7. Habilitar serviços do sistema ────────────────────────
info "Habilitando serviços..."
sudo systemctl enable NetworkManager

# pipewire/wireplumber como serviços de usuário
systemctl --user enable pipewire pipewire-pulse wireplumber

# ── 8. Numlock ligado no boot ────────────────────────────────
info "Configurando numlock ligado no boot..."
# Desabilita serviço antigo caso exista
sudo systemctl disable numlock-off.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/numlock-off.service
sudo cp "$DOTFILES_DIR/systemd/numlock-on.service" \
    /etc/systemd/system/numlock-on.service
sudo systemctl daemon-reload
sudo systemctl enable numlock-on.service

# ── 9. zram ────────────────────────────────────────────────
if [[ ! -f /etc/systemd/zram-generator.conf ]]; then
    info "Configurando zram..."
    sudo bash -c 'cat > /etc/systemd/zram-generator.conf << EOF
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF'
fi

# ── Fim ──────────────────────────────────────────────────────
echo ""
info "Setup concluído!"
echo ""
echo "  • Faça logout/login ou reinicie"
echo "  • No TTY, execute: Hyprland"
echo "  • Keybinds principais:"
echo "      Super + Enter     → kitty"
echo "      Super + Shift+Enter → brave"
echo "      Super + R         → rofi (launcher)"
echo "      Super + Q         → fechar janela"
echo "      Super + M         → sair do Hyprland"
echo ""
