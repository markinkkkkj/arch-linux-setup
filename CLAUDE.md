# Provisioning script — Arch Linux + Sway (ThinkPad T14 Gen 1)

This repository contains `install.sh`, a personal provisioning script for a real
Arch Linux machine, with a Sway/Wayland graphical environment. The context below
comes from the current `install.sh` and from `relato.txt` (output of a hardware
audit script run on the machine itself). `relato.txt` is the source of truth about
the hardware — any package or configuration decision should be traceable back to it.

## Target hardware

- **Model:** ThinkPad T14 Gen 1, `20S1002LBR` (Brazilian variant, ABNT2 keyboard).
  BIOS `N2XET45W (1.35)`.
- **CPU:** Intel Core i7-10610U (Comet Lake), 4 cores / 8 threads. Intel microcode
  required (`intel-ucode`, already installed).
- **GPU:** Intel UHD Graphics (CometLake-U GT2), `i915` driver already loaded.
  Missing `vulkan-intel` and `intel-media-driver` for full video/Vulkan acceleration.
- **Wi-Fi:** Intel AX201 (Wi-Fi 6) via the `iwlwifi` driver, working.
- **Ethernet:** Intel I219-LM via the `e1000e` driver, working (port unplugged at
  audit time).
- **Bluetooth:** radio exists and is not blocked (rfkill), but **`bluez` is not
  installed** and the `bluetooth` service is inactive/absent. `blueman` is also
  missing.
- **Audio (most sensitive section):** Intel HDA controller with SOF
  (`sof-audio-pci-intel-cnl` / `snd_sof_pci_intel_cnl`), ALSA card registered as
  `sof-hda-dsp`. Realtek codec from the `alc269` driver family (the hardware is
  marketed as ALC257; the kernel groups several Realtek codecs under the "alc269"
  driver). SOF firmware for Comet Lake (`sof-cml.ri` / `sof-cml.ldc`) already on
  disk, and packages `sof-firmware`, `alsa-ucm-conf`, `alsa-utils`, `pipewire`,
  `pipewire-pulse`, `pipewire-alsa`, `wireplumber`, `pavucontrol` already installed
  — the audio stack already works (sink `HiFi__Speaker__sink` active). **Do not
  assume firmware is missing**: the real concern here is keeping these packages
  installed, not installing them from scratch.
- **Webcam:** built-in, works via v4l2 (no failure reported in the audit).
- **Battery:** health at ~82.7% (`energy-full` 42.17Wh vs `energy-full-design`
  51Wh) — justifies capping charge at 80% via TLP to avoid further degradation.
- **Backlight:** controlled via `intel_backlight` (sysfs), use with
  `brightnessctl` (currently missing).

## Partitioning (CRITICAL)

Single disk `nvme0n1` (476.9G), **triple boot**:

| Partition     | Size    | FS    | Mount point | Role                                     |
|---------------|---------|-------|-------------|-------------------------------------------|
| nvme0n1p1     | 1G      | vfat  | `/boot`     | **Shared ESP** (Windows + Linux GRUB/systemd-boot + macOS OpenCore) |
| nvme0n1p2     | 16M     | —     | —           | Microsoft Reserved (MSR), Windows          |
| nvme0n1p3     | 149.2G  | ntfs  | —           | Windows (data/OS)                          |
| nvme0n1p4     | 780M    | ntfs  | —           | Windows (recovery/reserved)                |
| nvme0n1p5     | 165G    | ext4  | `/`         | **Arch Linux root**                        |
| nvme0n1p6     | 160.9G  | apfs  | —           | macOS (hackintosh via OpenCore)            |

The 1 GB ESP mounted at `/boot` is shared between all three systems. Any wrong
write there can break boot for all of them. `fstab` is already correct and must
not be touched by this script.

## Environment

- **Session:** Sway (Wayland), started manually from the TTY — no display
  manager. Today `XDG_CURRENT_DESKTOP` is empty and no polkit agent or
  notification daemon is running (confirmed by the audit).
- **Visible stack:** `foot` terminal, `waybar` bar, `wofi` launcher, Zen Browser
  (AUR, `zen-browser-bin`), VS Code editor (AUR, `visual-studio-code-bin`).
- **XDG portals:** `xdg-desktop-portal`, `-wlr` and `-gtk` already installed and
  all three already show up on the D-Bus bus in the audit.
- **AUR:** via `yay` (helper not yet installed at audit time — the script's
  `check_yay` handles this).
- **Dotfiles:** managed with GNU Stow (`stow` package **missing** today).
- **Locale:** `en_US.UTF-8` already configured. **Note:** console and X11
  keyboard are still set to `us`, but the machine is ABNT2 — needs to become
  `br-abnt2`.
- **zram:** 4 GB already configured (`zram-generator` installed, `/dev/zram0`
  active).

## Usage

Software development, with an interest in Flutter.

## Current state (audit summary — what's missing today)

Key packages missing per `relato.txt` (use as a checklist for upcoming prompts,
not as a final list — it will still be validated package by package against the
repositories): `vulkan-intel`, `intel-media-driver`, `bluez`, `blueman`,
`xorg-xwayland`, `gnome-keyring`, `mako`, `brightnessctl`, `gvfs`, `gvfs-mtp`,
`udisks2`, `udiskie`, `thunar`, `tumbler`, `noto-fonts`, `noto-fonts-emoji`,
`noto-fonts-cjk`, `ttf-jetbrains-mono-nerd`, `qt5ct`, `qt6ct`, `xdg-user-dirs`,
`cups`, `nss-mdns`, `ntfs-3g`, `exfatprogs`, `gst-plugins-good`,
`gst-plugin-pipewire`, `stow`.

No power manager (TLP / power-profiles-daemon / thermald) is installed or active
yet — the script is free to choose, but the rules below already commit to TLP.

## Inviolable rules for any code generated in this project

1. **NEVER** write, move, delete, or reformat anything inside `/boot` — it's the
   shared ESP; a mistake there breaks boot for all three operating systems.
2. **NEVER** modify the partition table, nor run `mkfs`, `fdisk`, `parted`, or
   `dd`.
3. **NEVER** run `install.sh`'s installation or configuration steps on this
   machine — those only happen in a container. Demonstrably read-only paths
   are fine to run here: `--help`, `--dry-run`, and `--doctor`.
4. Every `rm -rf` must have its path validated as non-empty/non-root before
   running.
5. Never enable `tlp` and `power-profiles-daemon` together — they conflict.
6. The script runs as a normal user and escalates with `sudo` at specific
   points; never as root.
