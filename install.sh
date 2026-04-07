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

# ── 2. Instalar zsh e configurar como shell padrão ──────────
info "Instalando zsh..."
sudo pacman -S --needed --noconfirm \
    zsh \
    zsh-autosuggestions \
    zsh-syntax-highlighting

info "Configurando zsh..."
cp "$DOTFILES_DIR/zsh/.zshrc" ~/.zshrc

if [[ "$SHELL" != "$(which zsh)" ]]; then
    info "Definindo zsh como shell padrão..."
    chsh -s "$(which zsh)"
fi

# ── 3. Instalar dependências base ────────────────────────────
info "Instalando pacotes base..."
sudo pacman -S --needed --noconfirm \
    base-devel git sudo curl wget unzip \
    linux-firmware intel-ucode sof-firmware \
    iwd networkmanager sway \
    pipewire pipewire-alsa pipewire-pulse wireplumber rtkit alsa-utils \
    hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
    waybar \
    kitty \
    rofi \
    numlockx \
    ttf-jetbrains-mono-nerd noto-fonts-emoji \
    pavucontrol \
    imagemagick ffmpegthumbnailer perl-image-exiftool \
    eog gedit neovim \
    yazi \
    zram-generator \
    efibootmgr refind \
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
sudo systemctl enable iwd

# pipewire/wireplumber como serviços de usuário
systemctl --user enable pipewire pipewire-pulse wireplumber

# ── 8. Serviço de fix do audio (Intel SOF boot race) ────────
# O driver SOF inicializa com perfil "Line" (saída de linha) em vez de
# "Speaker", e às vezes perde o wireplumber na corrida de boot.
# O serviço reinicia o wireplumber e força o perfil correto.
info "Configurando serviço de fix de áudio..."
mkdir -p ~/.config/systemd/user
cp "$DOTFILES_DIR/systemd/wireplumber-restart.service" \
    ~/.config/systemd/user/wireplumber-restart.service
systemctl --user daemon-reload
systemctl --user enable wireplumber-restart.service

# ── 9. Numlock ligado no boot ────────────────────────────────
info "Configurando numlock ligado no boot..."
# Desabilita serviço antigo caso exista
sudo systemctl disable numlock-off.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/numlock-off.service
sudo cp "$DOTFILES_DIR/systemd/numlock-on.service" \
    /etc/systemd/system/numlock-on.service
sudo systemctl daemon-reload
sudo systemctl enable numlock-on.service

# ── 10. Configurar rEFInd ────────────────────────────────────
info "Instalando e configurando rEFInd..."

# Instala o rEFInd na partição EFI
sudo refind-install

# Detecta o diretório do rEFInd (varia por distro/firmware)
REFIND_DIR=""
for candidate in /boot/EFI/refind /boot/efi/EFI/refind /efi/EFI/refind; do
    if [[ -d "$candidate" ]]; then
        REFIND_DIR="$candidate"
        break
    fi
done

if [[ -z "$REFIND_DIR" ]]; then
    error "Diretório do rEFInd não encontrado. Verifique se o refind-install foi executado."
    exit 1
fi

# Instala o tema darkmini
THEME_DIR="$REFIND_DIR/themes/darkmini"
if [[ -d "$THEME_DIR/.git" ]]; then
    info "Atualizando tema darkmini..."
    sudo git -C "$THEME_DIR" pull --ff-only
elif [[ -d "$THEME_DIR" ]]; then
    info "Pasta do tema já existe (sem git), pulando."
else
    info "Clonando tema darkmini..."
    sudo mkdir -p "$REFIND_DIR/themes"
    sudo git clone https://github.com/LightAir/darkmini.git "$THEME_DIR"
fi

# Detecta UUID da partição root e kernel mais recente
ROOT_UUID=$(findmnt -n -o UUID /)

KERNEL_PATH=$(ls /boot/vmlinuz-* 2>/dev/null | sort -V | tail -1)
if [[ -z "$KERNEL_PATH" ]]; then
    error "Nenhum kernel encontrado em /boot. Verifique a instalação."
    exit 1
fi
KERNEL_VER="${KERNEL_PATH#/boot/vmlinuz-}"

REFIND_CONF="$REFIND_DIR/refind.conf"

# Ativa o tema no refind.conf
if ! grep -q "include themes/darkmini/theme.conf" "$REFIND_CONF"; then
    echo -e "\ninclude themes/darkmini/theme.conf" | sudo tee -a "$REFIND_CONF" > /dev/null
    info "Tema darkmini ativado no rEFInd."
else
    info "Tema darkmini já está ativado, pulando."
fi

# Esconde a barra de ferramentas (shutdown, reboot, etc.)
if ! grep -q "^showtools" "$REFIND_CONF"; then
    echo -e "\nshowtools" | sudo tee -a "$REFIND_CONF" > /dev/null
    info "Barra de tools desabilitada no rEFInd."
else
    info "showtools já configurado, pulando."
fi

# Desabilita auto-scan do Windows para controlar a ordem de exibição.
# Sem isso, entradas auto-detectadas aparecem antes das entradas manuais.
if ! grep -q "dont_scan_dirs" "$REFIND_CONF"; then
    echo -e "\ndont_scan_dirs EFI/Microsoft" | sudo tee -a "$REFIND_CONF" > /dev/null
    info "Auto-scan do Windows desabilitado no rEFInd."
else
    info "dont_scan_dirs já configurado, pulando."
fi

# Detecta caminho do bootloader do Windows (Microsoft Boot Manager)
WIN_LOADER=""
for candidate in /boot/EFI/Microsoft/Boot/bootmgfw.efi \
                 /boot/efi/EFI/Microsoft/Boot/bootmgfw.efi \
                 /efi/EFI/Microsoft/Boot/bootmgfw.efi; do
    if [[ -f "$candidate" ]]; then
        # Converte para caminho relativo à partição EFI (formato rEFInd)
        WIN_LOADER="/EFI/Microsoft/Boot/bootmgfw.efi"
        break
    fi
done

# Adiciona entradas manuais: Windows primeiro, Arch Linux depois
if [[ -n "$WIN_LOADER" ]]; then
    WIN_STANZA=$(cat <<EOF

menuentry "Windows" {
    icon    themes/darkmini/icons/os_win.png
    loader  ${WIN_LOADER}
}
EOF
)
    if ! grep -q "menuentry \"Windows\"" "$REFIND_CONF"; then
        echo "$WIN_STANZA" | sudo tee -a "$REFIND_CONF" > /dev/null
        info "Entrada do Windows adicionada ao rEFInd."
    else
        info "Entrada do Windows já existe no rEFInd, pulando."
    fi
else
    warn "Bootloader do Windows não encontrado — entrada do Windows não adicionada."
fi

STANZA=$(cat <<EOF

menuentry "Arch Linux" {
    icon     themes/darkmini/icons/os_arch.png
    volume   "Arch Linux"
    loader   /vmlinuz-${KERNEL_VER}
    initrd   /initramfs-${KERNEL_VER}.img
    options  "root=UUID=${ROOT_UUID} rw quiet splash"
    submenuentry "Boot com fallback initramfs" {
        initrd /initramfs-${KERNEL_VER}-fallback.img
    }
    submenuentry "Boot para terminal (recovery)" {
        add_options "systemd.unit=rescue.target"
    }
}
EOF
)

if ! grep -q "menuentry \"Arch Linux\"" "$REFIND_CONF"; then
    echo "$STANZA" | sudo tee -a "$REFIND_CONF" > /dev/null
    info "Entrada do Arch Linux adicionada ao rEFInd."
else
    info "Entrada do Arch Linux já existe no rEFInd, pulando."
fi

# ── 11. zram ────────────────────────────────────────────────
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
warn "Se o áudio não funcionar no primeiro boot, reinicie uma vez – o serviço wireplumber-restart.service vai corrigir automaticamente."
