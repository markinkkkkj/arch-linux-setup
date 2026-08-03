#!/usr/bin/env bash
#
# test.sh -- runs install.sh and dotfiles.sh inside a throwaway Arch
# container, so nothing touches the real machine.
#
# The repo is COPIED into the container (never bind-mounted): the scripts
# write backups, generate snippets and create symlinks, and none of that
# should land on the host's working tree.
#
# Usage:
#   ./test.sh              # dry-run, then a real run skipping the aur group
#   ./test.sh --with-aur   # also build the AUR packages (slow: compiles yay)
#   ./test.sh --shell      # drop into a shell in the prepared container
#   ./test.sh --keep       # leave the container running for inspection

set -Eeuo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[i]$1${NC}"; }
warn()    { echo -e "${YELLOW}[!]$1${NC}"; }
success() { echo -e "${GREEN}[✓]$1${NC}"; }
error()   { echo -e "${RED}[✗]$1${NC}"; }

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE=linux-setup-test
CONTAINER=linux-setup-test-run
WITH_AUR=false
SHELL_ONLY=false
KEEP=false

for arg in "$@"; do
    case "$arg" in
        --with-aur) WITH_AUR=true ;;
        --shell) SHELL_ONLY=true ;;
        --keep) KEEP=true ;;
        --help)
            sed -n '3,14p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
            exit 0
            ;;
        *) error "Unknown option: $arg"; exit 1 ;;
    esac
done

DOCKER=docker
command -v "$DOCKER" >/dev/null 2>&1 || { error "docker not found."; exit 1; }

cleanup() {
    if $KEEP; then
        warn "Keeping the container '$CONTAINER' for inspection (--keep):"
        warn "  docker exec -it -u tester -w /home/tester/linux-setup $CONTAINER bash"
        warn "  docker rm -f $CONTAINER"
        return 0
    fi
    "$DOCKER" rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Build and start
# ---------------------------------------------------------------------------

info "Building the image ($IMAGE)..."
"$DOCKER" build -q -t "$IMAGE" "$SCRIPT_DIR" >/dev/null

cleanup
info "Starting the container..."
# The pacman cache lives in a named volume so re-runs don't re-download ~1GB
# of packages. Delete it with:
#   docker volume rm linux-setup-pacman-cache
"$DOCKER" run -d --name "$CONTAINER" \
    -v linux-setup-pacman-cache:/var/cache/pacman/pkg \
    "$IMAGE" sleep infinity >/dev/null

# Copy the repo in, excluding .git and any host-side build noise.
info "Copying the repository into the container..."
tar -C "$SCRIPT_DIR" --exclude=.git --exclude='*.log' -cf - . |
    "$DOCKER" exec -i -u tester "$CONTAINER" tar -C /home/tester/linux-setup -xf -

run_in() { "$DOCKER" exec -u tester -w /home/tester/linux-setup "$CONTAINER" bash -c "$1"; }

if $SHELL_ONLY; then
    info "Dropping into the container shell."
    "$DOCKER" exec -it -u tester -w /home/tester/linux-setup "$CONTAINER" bash
    exit 0
fi

# ---------------------------------------------------------------------------
# Phases -- each records its exit code instead of aborting the harness, so
# one failure doesn't hide the results of everything after it.
# ---------------------------------------------------------------------------

declare -A RESULTS
phase() {
    local name="$1" cmd="$2" rc=0
    echo
    info "=== $name ==="
    run_in "$cmd" || rc=$?
    RESULTS["$name"]=$rc
    if [[ $rc -eq 0 ]]; then
        success "$name: exit 0"
    else
        error "$name: exit $rc"
    fi
    return 0
}

phase "help" "./install.sh --help"

phase "dry-run" "./install.sh --dry-run --yes"

SKIP_ARG="--skip=aur"
if $WITH_AUR; then
    SKIP_ARG=""
    warn "Including the aur group: yay and every AUR package get compiled. This is slow."
else
    warn "Skipping the aur group by default (compiling yay + AUR packages is slow and"
    warn "network-heavy). Use --with-aur to exercise it."
fi

phase "real run" "./install.sh --yes $SKIP_ARG"

# dotfiles conflict path: a REAL file already sitting where a stow package
# wants to link must be moved to the backup, never destroyed.
phase "dotfiles conflict" '
set -e
mkdir -p "$HOME/.config/foot"
echo "PRECIOUS-HANDMADE-CONFIG" > "$HOME/.config/foot/foot.ini"
./dotfiles.sh --yes
echo "--- backup contents ---"
found=$(grep -rl PRECIOUS-HANDMADE-CONFIG "$HOME"/dotfiles-backup-* 2>/dev/null || true)
if [ -z "$found" ]; then
    echo "FAIL: the original file was not preserved in the backup"
    exit 1
fi
echo "original preserved at: $found"
if [ ! -L "$HOME/.config/foot/foot.ini" ] && [ ! -L "$HOME/.config/foot" ]; then
    echo "FAIL: the dotfile was not linked into place"
    exit 1
fi
echo "stow link in place: OK"
'

# Regression guard for a real data-loss bug: stow "tree folding" links a
# whole directory (~/.config/sway -> dotfiles/sway/.config/sway), so files
# inside it are real files behind a symlinked parent. Conflict detection
# that only tested `-L` on the file itself flagged them as conflicts, and
# the second run MOVED them out of the repository into the backup, emptying
# the stow packages. The re-run must leave dotfiles/ byte-for-byte intact.
phase "dotfiles idempotent re-run" '
set -e
before=$(find dotfiles -type f -o -type l | sort | xargs -r md5sum 2>/dev/null | md5sum)
./dotfiles.sh --yes
after=$(find dotfiles -type f -o -type l | sort | xargs -r md5sum 2>/dev/null | md5sum)
if [ "$before" != "$after" ]; then
    echo "FAIL: re-running dotfiles.sh modified the repository contents"
    echo "      (tree-folding conflict bug -- files moved out of dotfiles/)"
    exit 1
fi
echo "repository dotfiles/ unchanged by the re-run: OK"
'

phase "doctor" "./install.sh --doctor"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo
info "=== Packages that failed to install ==="
# Only the block install_pkgs prints under its own header -- doctor's
# "declared but not installed" list uses a similar bullet format and would
# otherwise be reported here as if it were an install failure.
run_in "awk '/The following packages were not installed:/{f=1;next} f&&/^  - /{print;next} f{f=0}' ~/arch-setup-*.log 2>/dev/null | sort -u" |
    grep . || info "(none -- every package installed)"

echo
info "=== Summary ==="
overall=0
for name in "help" "dry-run" "real run" "dotfiles conflict" "dotfiles idempotent re-run" "doctor"; do
    rc="${RESULTS[$name]:-skipped}"
    if [[ "$rc" == "0" ]]; then
        success "$(printf '%-28s' "$name") exit 0"
    else
        error "$(printf '%-28s' "$name") exit $rc"
        # --doctor is expected to be non-zero in a container: no hardware, no
        # graphical session, no systemd. It's reported, not counted as a
        # harness failure.
        [[ "$name" == "doctor" ]] || overall=1
    fi
done

echo
if [[ $overall -eq 0 ]]; then
    success "Container test passed."
else
    error "Container test FAILED."
fi
exit $overall
