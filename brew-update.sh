#!/usr/bin/env bash
set -Eeuo pipefail

BREW="/home/linuxbrew/.linuxbrew/bin/brew"
APP_NAME="Homebrew"

info() { printf '%s\n' "$*"; }

# Check brew is available
if ! command -v "$BREW" >/dev/null 2>&1; then
    printf 'error: %s not found\n' "$BREW" >&2
    exit 1
fi

current_version="$("$BREW" --version | head -1)"
info "updating $APP_NAME"
info "installed version: $current_version"

# Update brew itself, then upgrade all packages (assume yes to avoid interactive prompt)
"$BREW" update
"$BREW" upgrade --greedy -y

new_version="$("$BREW" --version | head -1)"
info "installed version: $new_version"
info "done"
