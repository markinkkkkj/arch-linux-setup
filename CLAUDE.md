# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Arch Linux + Hyprland dotfiles repository. The primary artifact is `install.sh`, a single-file setup script that provisions a complete Wayland desktop environment on a fresh Arch Linux installation.

## Running the Installer

```bash
# Full installation (must NOT run as root)
bash install.sh

# The script uses `set -e` — it exits on any error
```

There are no build, lint, or test commands — this is a shell script + config files repo.

## Architecture

### install.sh structure

The script runs 11 sequential steps, each announced with colored log output:

1. **System update** — `pacman -Syu`
2. **Zsh** — install + set as default shell
3. **Base packages** — pacman installs (firmware, audio, Hyprland stack, fonts, tools)
4. **yay** — AUR helper (cloned from AUR, built with makepkg)
5. **AUR packages** — `awww` (wallpaper daemon), `brave-bin`
6. **Config deployment** — copies `./hypr/`, `./waybar/`, `./kitty/`, `./yazi/`, `./zsh/` → `~/.config/`; applies `sed` path substitution in `hyprpaper.conf` to replace hardcoded `/home/[^/]*/` with `$HOME/`
7. **System services** — NetworkManager, iwd
8. **User services** — pipewire stack; `wireplumber-restart.service` fixes Intel SOF boot race condition (driver defaults to wrong audio profile)
9. **NumLock** — `numlock-on.service` sets NumLock LED via sysfs + `setleds` on TTYs
10. **rEFInd** — installs bootloader, refindTTL theme, auto-generates boot entries (detects kernel via `ls /boot/vmlinuz-*`, gets root UUID via `findmnt`, optionally adds Windows entry)
11. **zram** — half-RAM zram with zstd via `/etc/systemd/zram-generator.conf`

### Scripting patterns

- **Idempotency**: `command -v`, `grep` checks, and directory existence tests guard every install/clone step — safe to re-run
- **Kernel detection**: use `ls /boot/vmlinuz-*` and strip the prefix manually; never use `xargs basename` on a glob (may be empty)
- **rEFInd tools bar**: use `showtools` with no arguments to hide the bottom shutdown/reboot bar; `hideui tools` is NOT a valid option and is silently ignored. `hideui` only accepts: `banner`, `label`, `singleuser`, `hints`, `arrows`, `badges`, `hwtest`, `progbar`, `editor`
- **rEFInd `volume`**: when the kernel lives on the EFI partition (i.e. `/boot` is the EFI mount), omit `volume` entirely — specifying a device name like `"nvme0n1p1"` won't match (rEFInd matches filesystem labels or GPT partition labels, not device paths)
- **Heredoc configs**: multi-line service files and rEFInd stanzas are written with `cat <<EOF`
- **Path substitution**: `sed "s|/home/[^/]*/|$HOME/|g"` normalizes hardcoded paths in configs

### Config files

| Directory | Tool | Notes |
|-----------|------|-------|
| `hypr/` | Hyprland | `hyprland.conf` — monitor `eDP-1` @ 1920×1080 60Hz 1.20× scale, Brazilian keyboard, dwindle layout |
| `waybar/` | Waybar | `config.jsonc` + `style.css` — dark theme, workspace dots, CPU/mem/battery/audio modules |
| `kitty/` | Kitty | JetBrainsMono Nerd Font 12pt |
| `yazi/` | Yazi | vim-style keys, dirs-first sorting, `$EDITOR` for text/JSON |
| `zsh/` | Zsh | `.zshrc` with autosuggestions + syntax-highlighting (pacman packages, not OMZ) |
| `systemd/` | systemd | `wireplumber-restart.service`, `numlock-on.service`, `numlock-off.service` |
