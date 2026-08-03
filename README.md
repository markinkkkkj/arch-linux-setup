# linux-setup

Personal provisioning for an Arch Linux + Sway ThinkPad T14 Gen 1
(`install.sh`, `dotfiles.sh`). The full README — flags, package groups,
troubleshooting — comes with the README step of `prompts-claude-code.md`;
this file starts with what already applies.

## Testing in a container

`install.sh` is never run on the real machine to test it. `test.sh` spins up
a throwaway Arch container and exercises the whole thing there:

```sh
./test.sh              # dry-run, then a real run (skipping the aur group)
./test.sh --with-aur   # also compile yay and the AUR packages (slow)
./test.sh --shell      # drop into a shell in the prepared container
./test.sh --keep       # leave the container running afterwards, to inspect it
```

Downloaded packages are cached in a named docker volume so re-runs don't
pull ~1 GB again; drop it with `docker volume rm linux-setup-pacman-cache`.

The repo is **copied** into the container, never bind-mounted, so backups,
generated snippets and stow symlinks can't land on the host working tree.
The harness records each phase's exit code instead of aborting, runs
`install.sh --help`, `--dry-run`, the real install, `dotfiles.sh` (including
the conflict path: a real `~/.config` file that collides with a stow package
must end up in the backup, not deleted), an idempotent re-run, and
`--doctor`, then prints the failed-package summary.

The re-run phase also asserts that `dotfiles/` is byte-for-byte unchanged.
That guards a real data-loss bug this test caught: under stow's *tree
folding* a whole directory is symlinked, so the files inside it are real
files behind a linked parent. Conflict detection that only tested `-L` on
the file itself flagged them as conflicts, and the second run moved them
out of the repository into the backup, emptying the stow packages.

The only read-only paths that may be run on the real machine are `--help`,
`--dry-run` and `--doctor`.

### What the container cannot test

The container has no hardware, no systemd as PID 1 and no graphical
session, so these need manual validation on the real machine:

| Area | Why the container can't cover it |
|---|---|
| Audio (SOF firmware, ALSA card, PipeWire sinks) | No sound hardware; the SOF DSP firmware is never loaded. |
| Backlight (`brightnessctl`) | No `intel_backlight` sysfs device. |
| Firmware updates (`fwupd`) | No real EFI/EC to talk to. |
| Video acceleration (`vainfo`, VA-API) | No Intel GPU / DRM device. |
| Bluetooth | No radio, no rfkill. |
| Enabling services (`systemctl enable --now`) | systemd isn't PID 1 in the container. |
| TLP vs power-profiles-daemon conflict check | Needs the services actually running. |
| Battery charge cap (80% via TLP) | No battery. |
| Graphical session checks (Wayland, XWayland, `XDG_CURRENT_DESKTOP`) | No compositor running. |
| XDG portals on the D-Bus session bus | No session bus with the portal backends. |
| Polkit agent / notification daemon | Started by the Sway config, which never runs here. |
| Default applications (`xdg-mime`) | The MIME database exists, but the handlers are GUI apps. |
| Sway config itself (keybinds, lock on lid close) | Needs a real compositor and a lid. |
| User group membership taking effect (`video`, `input`, `docker`) | Requires a real re-login. |

After a real run on the machine, `./install.sh --doctor` is the fastest way
to check the parts above.

## Repository hygiene & secrets

This repo holds dotfiles and may become public. Two layers keep secrets out:

1. **`.gitignore`** covers the typical dotfiles leak vectors (SSH/GPG private
   keys, `known_hosts`, CLI credential files for gh/aws/gcloud/npm/docker,
   `.env` files, shell history, browser databases, caches, editor sync
   state).
2. **`scripts/check-secrets.sh`** scans everything git would commit (the
   index) for credential-looking content: private key blocks, known token
   prefixes (GitHub, AWS, Slack, Google, npm, Docker, GitLab, OpenAI),
   suspicious variable assignments (`*_TOKEN`, `*_SECRET`, `*_PASSWORD`,
   `*_KEY`, …), and URLs with embedded credentials. Non-zero exit if
   anything is found.

Git does not version hooks, so install the pre-commit hook explicitly after
cloning:

```sh
./scripts/check-secrets.sh --install-hook
```

After that, every `git commit` runs the scan automatically and blocks the
commit on findings. It can also be run by hand at any time:

```sh
./scripts/check-secrets.sh
```

### If a secret does get committed

Deleting the file and committing again is **not** enough: the secret remains
reachable in git history (and in any clone or remote that already fetched
it). Treat the credential as **compromised and rotate it immediately** —
rewriting history (`git filter-repo`) only makes sense after the rotation,
and only if the repo hasn't been shared.
