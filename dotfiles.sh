#!/usr/bin/env bash
#
# dotfiles.sh -- manages this repo's dotfiles with GNU Stow.
#
# Called by install.sh via --dotfiles, or run standalone. Stow packages live
# in the repo's dotfiles/ directory (not ~/dotfiles): each subdirectory is
# one stow package, e.g. dotfiles/sway/.config/sway/config, and gets
# symlinked into $HOME.

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

ASSUME_YES=false
ACTION="stow"          # stow | restow | delete
DELETE_PKG=""
MOVED_FILES=()

SKELETON_PKGS=(sway waybar foot wofi mako nvim zsh git)

# ---------------------------------------------------------------------------
# CLI flags
# ---------------------------------------------------------------------------

usage() {
    cat <<'EOF'
Usage: dotfiles.sh [options]

Manages the repo's dotfiles/ stow packages, symlinking them into $HOME.

Options:
  --restow           Re-apply all packages (stow -R); use after adding files.
  --delete PACKAGE   Remove the symlinks of one package (stow -D).
  --yes              Don't ask anything; assume the default answer.
  --help             Show this help and exit.

With no options, applies (stow -S) every package under dotfiles/.
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --restow) ACTION="restow"; shift ;;
            --delete)
                if [[ $# -lt 2 ]]; then
                    error "--delete requires a package name."
                    usage
                    exit 1
                fi
                ACTION="delete"; DELETE_PKG="$2"; shift 2
                ;;
            --delete=*) ACTION="delete"; DELETE_PKG="${1#--delete=}"; shift ;;
            --yes) ASSUME_YES=true; shift ;;
            --help) usage; exit 0 ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Interactive prompt (same semantics as install.sh's confirm)
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
# Paths -- resolved from the script's own location, following symlinks.
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
STOW_DIR="$SCRIPT_DIR/dotfiles"
TARGET_DIR="$HOME"
BACKUP_DIR="$HOME/dotfiles-backup-$(date +%Y%m%d)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

check_stow() {
    if ! command -v stow >/dev/null 2>&1; then
        error "GNU Stow is not installed (it's in install.sh's dev group). Aborting."
        exit 1
    fi
}

# Creates the expected package skeleton for any package dir that doesn't
# exist yet. Empty dirs are a no-op for stow, so this is always safe.
ensure_skeleton() {
    local pkg
    for pkg in "${SKELETON_PKGS[@]}"; do
        if [[ ! -d "$STOW_DIR/$pkg" ]]; then
            info "Creating skeleton for package '$pkg'."
            mkdir -p "$STOW_DIR/$pkg/.config/$pkg"
        fi
    done
}

# Every subdirectory of dotfiles/ is a stow package (plain files like
# README.md are ignored).
list_packages() {
    find "$STOW_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
}

# find_conflicts <pkg>
#
# Prints the package-relative path of every file that stow would want to
# link but whose target already exists in $HOME as something we don't own
# (a real file, or a symlink pointing outside the stow dir). Directories
# existing along the way are not conflicts -- stow merges into them.
find_conflicts() {
    local pkg="$1" rel target resolved

    (cd "$STOW_DIR/$pkg" && find . \( -type f -o -type l \) | sed 's|^\./||') |
    while IFS= read -r rel; do
        target="$TARGET_DIR/$rel"

        [[ -e "$target" || -L "$target" ]] || continue

        if [[ -L "$target" ]]; then
            resolved="$(readlink -f "$target" 2>/dev/null || true)"
            case "$resolved" in
                "$STOW_DIR"/*) continue ;;  # already ours
            esac
        fi

        printf '%s\n' "$rel"
    done
}

# backup_conflicts <conflict>...
#
# Moves (never deletes) each conflicting real file out of the way into
# $BACKUP_DIR, preserving its relative path, and records it for the final
# report.
backup_conflicts() {
    local rel
    for rel in "$@"; do
        mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
        mv "$TARGET_DIR/$rel" "$BACKUP_DIR/$rel"
        MOVED_FILES+=("$rel")
    done
}

# show_plan <stow-flag> <pkg>...
#
# Runs stow in simulate mode (-n) and shows what it would do. A conflicting
# simulate exits non-zero -- that's expected before we move conflicts away,
# so the exit code is tolerated here.
show_plan() {
    local flag="$1"; shift
    info "Plan (stow --simulate):"
    stow -n -v -d "$STOW_DIR" -t "$TARGET_DIR" "$flag" "$@" 2>&1 | sed 's/^/    /' || true
}

report_moved() {
    if [[ ${#MOVED_FILES[@]} -eq 0 ]]; then
        return 0
    fi
    warn "The following pre-existing files were moved to $BACKUP_DIR:"
    printf '    %s\n' "${MOVED_FILES[@]}"
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

do_stow() {
    local flag="$1" verb="$2"  # -S "stow" | -R "restow"
    local pkgs=() pkg conflicts=() pkg_conflicts

    ensure_skeleton

    mapfile -t pkgs < <(list_packages)
    if [[ ${#pkgs[@]} -eq 0 ]]; then
        warn "No packages found under $STOW_DIR -- nothing to do."
        return 0
    fi

    info "Packages: ${pkgs[*]}"

    for pkg in "${pkgs[@]}"; do
        mapfile -t pkg_conflicts < <(find_conflicts "$pkg")
        conflicts+=("${pkg_conflicts[@]}")
    done

    show_plan "$flag" "${pkgs[@]}"

    if [[ ${#conflicts[@]} -gt 0 ]]; then
        warn "These existing files conflict and will be MOVED to $BACKUP_DIR (never deleted):"
        printf '    %s\n' "${conflicts[@]}"
    fi

    if ! confirm "Apply ($verb ${#pkgs[@]} package(s))?" "y"; then
        info "Nothing applied."
        return 0
    fi

    if [[ ${#conflicts[@]} -gt 0 ]]; then
        backup_conflicts "${conflicts[@]}"
    fi

    stow -v -d "$STOW_DIR" -t "$TARGET_DIR" "$flag" "${pkgs[@]}"
    success "Done ($verb): ${pkgs[*]}"
    report_moved
}

do_delete() {
    if [[ ! -d "$STOW_DIR/$DELETE_PKG" ]]; then
        error "Package '$DELETE_PKG' does not exist under $STOW_DIR."
        exit 1
    fi

    show_plan -D "$DELETE_PKG"

    # Default "y": the user explicitly asked for --delete, the confirm is
    # only a chance to review the plan (and matters mostly interactively).
    if ! confirm "Remove the symlinks of package '$DELETE_PKG'?" "y"; then
        info "Nothing removed."
        return 0
    fi

    # stow -D only removes symlinks it owns; it never touches real files.
    stow -v -d "$STOW_DIR" -t "$TARGET_DIR" -D "$DELETE_PKG"
    success "Package '$DELETE_PKG' unstowed."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

parse_args "$@"
check_stow

case "$ACTION" in
    stow)   do_stow -S "stow" ;;
    restow) do_stow -R "restow" ;;
    delete) do_delete ;;
esac
