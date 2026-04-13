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
    networkmanager sway which \
    pipewire pipewire-alsa pipewire-pulse wireplumber rtkit alsa-utils \
    hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
    hyprpaper \
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
    efibootmgr

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
    brave-bin \
    visual-studio-code-bin

# ── 5b. pyenv ────────────────────────────────────────────────
if ! command -v pyenv &>/dev/null; then
    info "Instalando pyenv..."
    curl -fsSL https://pyenv.run | bash
else
    info "pyenv já instalado, pulando."
fi

# ── 5c. nvm ──────────────────────────────────────────────────
if [[ ! -d "$HOME/.nvm" ]]; then
    info "Instalando nvm..."
    NVM_LATEST=$(curl -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_LATEST}/install.sh" | bash
else
    info "nvm já instalado, pulando."
fi

# ── 6. Copiar configs ────────────────────────────────────────
info "Copiando configurações..."

mkdir -p ~/.config/hypr
cp "$DOTFILES_DIR/hypr/hyprland.conf"           ~/.config/hypr/hyprland.conf
cp "$DOTFILES_DIR/hypr/archlinux-wallpaper.png" ~/.config/hypr/archlinux-wallpaper.png

# hyprpaper.conf: expande $HOME para o caminho real do usuário
envsubst < "$DOTFILES_DIR/hypr/hyprpaper.conf" > ~/.config/hypr/hyprpaper.conf

mkdir -p ~/.config/waybar
cp "$DOTFILES_DIR/waybar/config.jsonc" ~/.config/waybar/config.jsonc
cp "$DOTFILES_DIR/waybar/style.css"    ~/.config/waybar/style.css

mkdir -p ~/.config/kitty
cp "$DOTFILES_DIR/kitty/kitty.conf" ~/.config/kitty/kitty.conf

mkdir -p ~/.config/yazi
cp "$DOTFILES_DIR/yazi/yazi.toml"   ~/.config/yazi/yazi.toml
cp "$DOTFILES_DIR/yazi/keymap.toml" ~/.config/yazi/keymap.toml

# Brave: rodar em modo Wayland nativo (GPU acceleration + DRM/Widevine funcionam corretamente)
grep -q -- '--ozone-platform=wayland' ~/.config/brave-flags.conf 2>/dev/null || \
    echo '--ozone-platform=wayland' >> ~/.config/brave-flags.conf

# atualizar cache de fontes após instalar noto-fonts-emoji
fc-cache -fv &>/dev/null

# ── 7. Habilitar serviços do sistema ────────────────────────
info "Habilitando serviços..."
sudo systemctl enable NetworkManager

# pipewire/wireplumber como serviços de usuário
systemctl --user enable pipewire pipewire-pulse wireplumber

# wireplumber-restart corrige race condition Intel SOF no boot
mkdir -p "$HOME/.config/systemd/user"
cp "$DOTFILES_DIR/systemd/wireplumber-restart.service" \
    "$HOME/.config/systemd/user/wireplumber-restart.service"
systemctl --user daemon-reload
systemctl --user enable wireplumber-restart.service

# ── 8. Numlock ligado no boot ────────────────────────────────
info "Configurando numlock ligado no boot..."
# Desabilita serviço antigo caso exista
sudo systemctl disable numlock-off.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/numlock-off.service
sudo cp "$DOTFILES_DIR/systemd/numlock-on.service" \
    /etc/systemd/system/numlock-on.service
sudo systemctl daemon-reload
sudo systemctl enable numlock-on.service

# ── 9. rEFInd bootloader ────────────────────────────────────
info "Instalando rEFInd 0.14.0.2..."

REFIND_VER="0.14.0.2"
REFIND_PKG="refind-${REFIND_VER}-2-x86_64.pkg.tar.zst"
REFIND_URL="https://archive.archlinux.org/packages/r/refind/${REFIND_PKG}"

if pacman -Q refind 2>/dev/null | grep -q "^refind ${REFIND_VER}-"; then
    info "rEFInd ${REFIND_VER} já instalado, pulando."
else
    # Remove versão anterior se instalada
    if pacman -Q refind &>/dev/null; then
        info "Removendo rEFInd $(pacman -Q refind | awk '{print $2}')..."
        sudo pacman -Rdd --noconfirm refind
    fi
    curl -L -o "/tmp/${REFIND_PKG}" "${REFIND_URL}"
    sudo pacman -U --noconfirm "/tmp/${REFIND_PKG}"
    rm "/tmp/${REFIND_PKG}"
fi

# Bloquear atualizações automáticas do rEFInd
if grep -qE '^IgnorePkg\s*=.*refind' /etc/pacman.conf; then
    info "rEFInd já fixado no IgnorePkg."
elif grep -qE '^IgnorePkg\s*=' /etc/pacman.conf; then
    sudo sed -i 's/^\(IgnorePkg\s*=.*\)/\1 refind/' /etc/pacman.conf
elif grep -qE '^#\s*IgnorePkg' /etc/pacman.conf; then
    sudo sed -i 's/^#\s*IgnorePkg\s*=.*/IgnorePkg = refind/' /etc/pacman.conf
else
    echo 'IgnorePkg = refind' | sudo tee -a /etc/pacman.conf > /dev/null
fi
info "rEFInd fixado na versão ${REFIND_VER} (IgnorePkg no pacman.conf)."

sudo refind-install

# Corrigir resolução gráfica do rEFInd — firmware Insyde (Acer) trava com a resolução
# padrão 800x600. "max" usa o modo GOP que o firmware já está usando, evitando o travamento.
REFIND_CONF="/boot/EFI/refind/refind.conf"
sudo sed -i 's/^#resolution max$/resolution max/' "$REFIND_CONF"
# Adiciona caso a linha ainda não exista descomentada
grep -q '^resolution max' "$REFIND_CONF" || echo 'resolution max' | sudo tee -a "$REFIND_CONF" > /dev/null
info "rEFInd: resolution max configurado."

# ── 10. zram ───────────────────────────────────────────────
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
