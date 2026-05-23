#!/usr/bin/env bash
# bx-purpose: install GitHub CLI (gh) from the official apt repo (idempotent)
set -euo pipefail

KEYRING=/etc/apt/keyrings/githubcli-archive-keyring.gpg
SOURCES=/etc/apt/sources.list.d/github-cli.list

main() {
    if command -v gh >/dev/null 2>&1; then
        printf 'gh already installed: %s\n' "$(gh --version 2>/dev/null | head -1)"
        return 0
    fi

    if ! sudo -n true 2>/dev/null; then
        echo "install-gh: this script needs sudo. Two ways to run it:"
        echo "  sudo bx run install-gh"
        echo "  sudo -v && bx run install-gh    # prime sudo cache, then re-run"
        return 1
    fi

    sudo mkdir -p -m 755 /etc/apt/keyrings

    if [[ ! -s "$KEYRING" ]]; then
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
            | sudo tee "$KEYRING" >/dev/null
        sudo chmod go+r "$KEYRING"
    fi

    local arch desired
    arch=$(dpkg --print-architecture)
    desired="deb [arch=${arch} signed-by=${KEYRING}] https://cli.github.com/packages stable main"
    if [[ ! -f "$SOURCES" ]] || ! grep -qF "$desired" "$SOURCES"; then
        echo "$desired" | sudo tee "$SOURCES" >/dev/null
    fi

    sudo apt-get update -qq
    sudo apt-get install -y gh

    printf 'gh installed: %s\n' "$(gh --version | head -1)"
}

main "$@"
