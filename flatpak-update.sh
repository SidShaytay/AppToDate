#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="Flatpak"

info() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

if ! command -v flatpak >/dev/null 2>&1; then
    printf 'error: flatpak not found\n' >&2
    exit 1
fi

info "updating $APP_NAME"
info "installed apps (before):"
flatpak list --columns=app,version 2>/dev/null | head -30

# Include commits: an update can keep the same human-readable version.
before="$(flatpak list --columns=application,arch,branch,origin,installation,active | LC_ALL=C sort)"
# Flatpak checks remote metadata and skips unchanged application content.
if ! flatpak update -y 2>&1; then
    warn 'flatpak update reported errors'
fi

after="$(flatpak list --columns=application,arch,branch,origin,installation,active | LC_ALL=C sort)"
if [[ "$before" == "$after" ]]; then
    info 'installed Flatpak commits are unchanged; skipping portal restart'
    exit 0
fi

# Restart portal so file pickers and portals work with updated apps
info "restarting flatpak-portal.service"
systemctl --user restart flatpak-portal.service 2>/dev/null || warn "failed to restart flatpak-portal.service"

info "done"
