# linux-setup

Provisioning script **and** dotfiles for my machine: an Arch Linux +
Sway/Wayland ThinkPad T14 Gen 1.

- `install.sh` — installs the packages, applies the system configuration and
  enables the services.
- `dotfiles.sh` — symlinks `dotfiles/` into `$HOME` with GNU Stow.
- `test.sh` — runs all of the above inside a throwaway container.

The machine is triple boot (Windows / Arch / macOS) sharing a single 1 GB
EFI partition, so nothing here ever touches `/boot`, the partition table or
the bootloader.

## Installation

On a fresh Arch install `git` is **not** part of `base`, so it has to be
installed before the repo can be cloned:

```sh
sudo pacman -S --needed git
git clone https://github.com/markinkkkkj/linux-setup.git
cd linux-setup
./install.sh
```

The script must run as a normal user (it refuses to run as root) and asks
for `sudo` at the specific points that need it.

It reads files from its own directory, so it has to run from the cloned
repo — there is no `curl | bash` install.

Worth doing first:

```sh
./install.sh --dry-run    # show everything it would do, changing nothing
```

## Flags

### `install.sh`

| Flag | What it does |
|---|---|
| `--dry-run` | Show what would be done, without installing or changing anything. |
| `--only=GROUP[,GROUP…]` | Run only the given groups. |
| `--skip=GROUP[,GROUP…]` | Skip the given groups. |
| `--dotfiles` | Also apply the dotfiles with GNU Stow (runs `dotfiles.sh`). |
| `--doctor` | Diagnostics only: report OK/WARN/FAIL per item, change nothing. Non-zero exit if anything FAILs. |
| `--yes` | Don't ask anything; assume each prompt's default answer. |
| `--help` | Show the built-in help. |

`--only`/`--skip` accept the package groups below, plus `config` (the system
configuration step) and `services` (the service-enabling step).

### `dotfiles.sh`

| Flag | What it does |
|---|---|
| *(none)* | Apply every package under `dotfiles/` (`stow -S`). |
| `--restow` | Re-apply everything (`stow -R`); use after adding files. |
| `--delete PACKAGE` | Remove one package's symlinks (`stow -D`). |
| `--yes` | Don't ask anything; assume the default answer. |
| `--help` | Show the built-in help. |

### `test.sh`

| Flag | What it does |
|---|---|
| *(none)* | Dry-run, then a real run in the container, skipping the `aur` group. |
| `--with-aur` | Also compile `yay` and the AUR packages (slow). |
| `--shell` | Drop into a shell in the prepared container. |
| `--keep` | Leave the container running afterwards, to inspect it. |

## Package groups

Installed in this order — it is **not** alphabetical. `audio` comes first on
purpose: `waybar` (in `base`) pulls in a virtual `jack` provider, and under
`--noconfirm` pacman would resolve that implicitly before `audio` gets to
install `pipewire-jack`, potentially dragging `jack2` into a clean install
and creating an unrecoverable conflict.

| Group | What it covers |
|---|---|
| `audio` | Full PipeWire stack (ALSA/Pulse/JACK compat), WirePlumber, diagnostics, volume GUI. |
| `base` | Core Sway session: compositor, bar, launcher, terminal, screenshots, clipboard. |
| `hardware` | This machine's drivers and firmware: Intel microcode, SOF audio firmware, Vulkan, VA-API, `fwupd`. |
| `session` | Wayland plumbing: XWayland, the three XDG portals, polkit agent, keyring, notification daemon. |
| `network` | Bluetooth stack and applets, firewall, tray applets. Wi-Fi already works out of the box. |
| `fonts` | Latin + CJK + emoji coverage, a Nerd Font for Waybar's icons, Microsoft-metric-compatible fonts. |
| `theme` | GTK/Qt look-and-feel consistency across toolkits. |
| `files` | File manager, thumbnails, automount, and read support for the NTFS and APFS partitions. |
| `apps` | One app per common file type, plus Firefox as a backup browser. |
| `codecs` | Extra GStreamer plugins for apps that don't go through PipeWire/mpv directly. |
| `printing` | CUPS and mDNS printer discovery on the local network. |
| `power` | TLP (never together with `power-profiles-daemon`), `thermald`, `brightnessctl`. |
| `dev` | Modern CLI tools, Docker, runtimes, and `stow`. |
| `aur` | AUR packages via `yay`: Zen Browser, VS Code, cursor theme, APFS FUSE driver. |

## Dotfiles

Each directory under `dotfiles/` is a **stow package** mirroring `$HOME`:

```
dotfiles/foot/.config/foot/foot.ini   →   ~/.config/foot/foot.ini
dotfiles/bash/.bashrc                 →   ~/.bashrc
```

Current packages: `bash`, `foot`, `git`, `gtk`, `mako`, `nvim`, `sway`,
`swayidle`, `swaylock`, `waybar`, `wofi`, `xdg-desktop-portal`, `zsh`
(some are still empty skeletons). The visual theme is monochrome
throughout — black, gray and white, no accent colors.

Apply them:

```sh
./dotfiles.sh              # shows the plan, asks, then applies
./dotfiles.sh --restow     # after adding files to a package
```

### Adding a new app

Create the package mirroring the path it should have in `$HOME`, then
restow:

```sh
mkdir -p dotfiles/kanshi/.config/kanshi
$EDITOR dotfiles/kanshi/.config/kanshi/config
./dotfiles.sh --restow
```

### Conflicts are never destroyed

If a real file already sits where a package wants to link, it is **moved**
to `~/dotfiles-backup-YYYYMMDD/` (preserving its relative path) and listed
at the end of the run. Nothing is ever overwritten or deleted.

### Moving the repo breaks every link

The symlinks point at this directory's absolute path. Moving or renaming the
repo folder breaks all of them at once — see troubleshooting below.

## Secrets hook

This repo holds dotfiles and may become public. `.gitignore` covers the
usual leak vectors (SSH/GPG keys, `known_hosts`, gh/aws/gcloud/npm/docker
credentials, `.env`, shell history, browser databases, editor sync state),
and `scripts/check-secrets.sh` scans everything git would commit for private
key blocks, known token prefixes, suspicious variable assignments and URLs
with embedded credentials.

Git does not version hooks, so install the pre-commit hook explicitly after
cloning:

```sh
./scripts/check-secrets.sh --install-hook
```

Every `git commit` then runs the scan and blocks on findings. Run it by hand
any time with `./scripts/check-secrets.sh`.

**If a secret does get committed**, deleting the file is not enough: it
stays reachable in git history and in any clone that already fetched it.
Treat the credential as compromised and **rotate it** — rewriting history
only makes sense after that.

## What you still have to do by hand

1. **Log out and back in** — the script adds you to the `video`, `input` and
   (if Docker was installed) `docker` groups, and group membership only
   takes effect on a new login session.
2. **Merge the generated Sway snippets.** The script writes
   `sway-keyboard-snippet.conf` and `sway-exec-snippet.conf` to the repo
   root instead of editing your Sway config, so you can review them first.
   The tracked `dotfiles/sway/.config/sway/config` already integrates both;
   the loose files matter only if you keep your own Sway config.
3. **Reboot for audio.** The SOF firmware is loaded by the kernel at boot,
   so a freshly installed `sof-firmware` only takes effect after a restart.
4. **Check the result:** `./install.sh --doctor`.

## Testing

`install.sh` is never run on the real machine to test it — only `--help`,
`--dry-run` and `--doctor` are safe here. Everything else goes through the
container:

```sh
./test.sh
```

The repo is copied into the container (never bind-mounted, so backups,
generated snippets and stow symlinks can't reach your working tree). Each
phase records its exit code instead of aborting: `--help`, `--dry-run`, the
real install, the dotfiles conflict path, an idempotent re-run, and
`--doctor`. Downloaded packages are cached in a named docker volume; drop it
with `docker volume rm linux-setup-pacman-cache`.

### What the container cannot test

No hardware, no systemd as PID 1, no graphical session — so these need
manual validation on the real machine:

| Area | Why the container can't cover it |
|---|---|
| Audio (SOF firmware, ALSA card, PipeWire sinks) | No sound hardware; the DSP firmware is never loaded. |
| Backlight (`brightnessctl`) | No `intel_backlight` sysfs device. |
| Firmware updates (`fwupd`) | No real EFI/EC to talk to. |
| Video acceleration (`vainfo`, VA-API) | No Intel GPU / DRM device. |
| Bluetooth | No radio, no rfkill. |
| Enabling services | systemd isn't PID 1; `systemctl enable --now` silently skips the start. |
| TLP vs power-profiles-daemon conflict | Needs the services actually running. |
| Battery charge cap (80% via TLP) | No battery. |
| Wayland / XWayland / `XDG_CURRENT_DESKTOP` checks | No compositor running. |
| XDG portals on the D-Bus session bus | No session bus with the portal backends. |
| Polkit agent / notification daemon | Started by the Sway config, which never runs here. |
| Default applications (`xdg-mime`) | The MIME database exists, but the handlers are GUI apps. |
| Sway config itself (keybinds, lock on lid close) | Needs a real compositor and a lid. |
| User groups taking effect | Requires a real re-login. |

## Troubleshooting

### No audio — no sink, or only `auto_null`

This machine's audio needs the SOF (Sound Open Firmware) DSP firmware; the
Realtek codec is driven through `sof-audio-pci-intel-cnl`, not plain HDA.
Without the firmware the card never registers and PipeWire falls back to a
dummy `auto_null` sink.

```sh
cat /proc/asound/cards          # should list sof-hda-dsp
ls /usr/lib/firmware/intel/sof/sof-cml*
pactl list short sinks          # should show a real sink, not auto_null
sudo dmesg | grep -i sof
```

Fix: make sure `sof-firmware` and `alsa-ucm-conf` are installed and
**reboot** — the firmware is only loaded at boot.

### An X11 app won't open

Anything that isn't Wayland-native (many Electron builds, older GTK2/Qt4
apps, some games) needs XWayland. If it's missing, `DISPLAY` is empty inside
the session and those apps fail to start, often with no visible error.

```sh
echo "$DISPLAY"                 # empty means XWayland isn't running
pacman -Qq xorg-xwayland
```

Fix: install `xorg-xwayland` and restart Sway. Sway starts XWayland on
demand, so no extra configuration is needed.

### The file picker doesn't appear in the browser

"Upload file" / "Save as" in Firefox or Zen goes through the XDG desktop
portal. The `wlr` backend implements screencast and screenshot only — the
file chooser comes from the **GTK** backend. If only `wlr` is on the bus,
the dialog silently never opens.

```sh
busctl --user list | grep portal   # look for impl.portal.desktop.gtk
echo "$XDG_CURRENT_DESKTOP"        # must not be empty
```

Two things are needed: `xdg-desktop-portal-gtk` installed, and
`XDG_CURRENT_DESKTOP` set — that variable is what makes the portal pick a
backend, and it is empty by default when Sway is started from a TTY. The
config step writes it to `~/.config/environment.d/`, which is read at login,
so **log out and back in** after applying it.

### `~/.config/foot` is a symlink to a directory, not individual files

That's normal, and it's how GNU Stow works. When a target directory doesn't
exist yet, stow links the whole directory at once ("tree folding") instead
of creating one symlink per file:

```
~/.config/foot -> ../Codes/linux-setup/dotfiles/foot/.config/foot
```

The practical consequences:

- Files you create inside `~/.config/foot/` land **in the repo** and show up
  in `git status`. That is usually what you want.
- **Moving or renaming the repo folder breaks every link at once**, because
  they point at its path. The symptom is a pile of dangling symlinks and
  apps falling back to their defaults. `./install.sh --doctor` reports
  broken symlinks under `~/.config` for exactly this reason. To fix, put the
  folder back, or re-link from the new location:

  ```sh
  ./dotfiles.sh --restow
  ```

- If a directory already exists in `$HOME`, stow can't fold it and links
  each file individually instead. Both layouts are valid and can coexist.

### Running the script outside a login shell

It works. The script deliberately uses `id -un` instead of `$USER` to find
out who it is running as: `$USER` is set by login shells and PAM, but not by
`docker exec`, `su -c` or cron, and an unset variable would abort the whole
run under `set -u`. So `sudo -u you ./install.sh`, a `docker exec` and a
plain non-login shell all behave the same.
