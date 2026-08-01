#!/usr/bin/env bash
#
# check-secrets.sh -- scans the files git would commit (the index) for
# credential-looking content. Exits non-zero if anything is found, so it
# works both standalone and as a pre-commit hook.
#
# Install as a pre-commit hook with:
#   ./scripts/check-secrets.sh --install-hook

set -Eeuo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'

info()    { echo -e "${BLUE}[i]$1${NC}"; }
warn()    { echo -e "${YELLOW}[!]$1${NC}"; }
success() { echo -e "${GREEN}[✓]$1${NC}"; }
error()   { echo -e "${RED}[✗]$1${NC}"; }

REPO_DIR="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    error "Not inside a git repository."
    exit 1
}
cd "$REPO_DIR"

# The scanner excludes itself: it necessarily contains every pattern it
# looks for.
EXCLUDE=(":(exclude)scripts/check-secrets.sh")

# label|extended-regex pairs, kept deliberately reviewable.
PATTERNS=(
    "private key block|-----BEGIN [A-Z ]*PRIVATE KEY( BLOCK)?-----"
    "GitHub token|\b((ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})"
    "AWS access key id|\bAKIA[0-9A-Z]{16}\b"
    "Slack token|\bxox[baprs]-[A-Za-z0-9-]{10,}"
    "Google API key|\bAIza[0-9A-Za-z_-]{30,}"
    "npm/Docker/GitLab token|\b(npm_|dckr_pat_|glpat-)[A-Za-z0-9_-]{20,}"
    "OpenAI-style secret key|\bsk-[A-Za-z0-9_-]{20,}\b"
    "credential variable assignment|[A-Za-z_]*(_TOKEN|_SECRET|_PASSWORD|_PASSWD|_API_KEY|_ACCESS_KEY|_PRIVATE_KEY|_KEY)[[:space:]]*[=:][[:space:]]*[\"']?[A-Za-z0-9+/=_.-]{8,}"
    "URL with embedded credential|[a-z][a-z0-9+.-]*://[^/[:space:]:@]+:[^/[:space:]@]+@"
)

install_hook() {
    local hook="$REPO_DIR/.git/hooks/pre-commit"
    local shim
    shim='#!/usr/bin/env bash
exec "$(git rev-parse --show-toplevel)/scripts/check-secrets.sh"'

    if [[ -e "$hook" ]] && ! grep -q "check-secrets.sh" "$hook"; then
        local backup="${hook}.bak-$(date +%Y%m%d)"
        warn "A different pre-commit hook exists; moving it to $backup."
        mv "$hook" "$backup"
    fi

    printf '%s\n' "$shim" > "$hook"
    chmod +x "$hook"
    success "Pre-commit hook installed at .git/hooks/pre-commit."
}

scan() {
    local found=0 entry label regex hits

    for entry in "${PATTERNS[@]}"; do
        label="${entry%%|*}"
        regex="${entry#*|}"

        # --cached scans the index: exactly what a commit would record.
        # -I skips binary files.
        hits="$(git grep --cached -nIE -e "$regex" -- "${EXCLUDE[@]}" || true)"

        if [[ -n "$hits" ]]; then
            error "Possible ${label}:"
            sed 's/^/    /' <<<"$hits"
            found=1
        fi
    done

    if [[ $found -ne 0 ]]; then
        echo
        error "Potential secrets found. Commit blocked -- review the matches above."
        warn "If something already got committed earlier, deleting the file is NOT enough: it stays in git history. Treat the credential as compromised and rotate it."
        return 1
    fi

    success "No credential-looking content in the files git would commit."
}

case "${1:-}" in
    --install-hook) install_hook ;;
    "") scan ;;
    *)
        error "Unknown option: $1 (use --install-hook, or no arguments to scan)"
        exit 1
        ;;
esac
