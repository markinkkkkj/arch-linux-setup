# dotfiles

GNU Stow packages for the environment (sway, waybar, foot, wofi, mako, nvim,
zsh, git), managed by `../dotfiles.sh` (run it directly, or via
`install.sh --dotfiles`).

Each subdirectory here is a stow package mirroring `$HOME`:
`<package>/.config/<app>/...` gets symlinked to `~/.config/<app>/...`.

- Apply everything: `./dotfiles.sh`
- Re-apply after adding files: `./dotfiles.sh --restow`
- Remove one package's symlinks: `./dotfiles.sh --delete <package>`

Pre-existing real files that would conflict are never overwritten or
deleted: they're moved to `~/dotfiles-backup-YYYYMMDD/` (preserving their
relative paths) and listed at the end of the run.
