# linux-setup

Personal provisioning for an Arch Linux + Sway ThinkPad T14 Gen 1
(`install.sh`, `dotfiles.sh`). The full README — flags, package groups,
troubleshooting — comes with the README step of `prompts-claude-code.md`;
this file starts with what already applies.

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
