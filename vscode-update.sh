#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="VSCode"
INSTALL_DIR="${HOME}/.local/share/vscode"
SYMLINK="${HOME}/.local/bin/code"
TMPDIR_BASE="/tmp"

info() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

if [[ ! -d "$INSTALL_DIR" ]]; then
    printf 'error: VSCode install directory not found: %s\n' "$INSTALL_DIR" >&2
    exit 1
fi

current_version="$(cat "$INSTALL_DIR/resources/app/package.json" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('version','?'))" 2>/dev/null || echo "?")"
info "updating $APP_NAME"
info "installed version: $current_version"

api_response="$(curl -sS --connect-timeout 15 "https://update.code.visualstudio.com/api/update/linux-x64/stable/latest" 2>/dev/null || echo "")"
if [[ -z "$api_response" ]]; then
    warn 'could not query latest version from Microsoft update API'
    exit 1
fi

latest_version="$(echo "$api_response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('productVersion',''))" 2>/dev/null || echo "")"
download_url="$(echo "$api_response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('url',''))" 2>/dev/null || echo "")"

if [[ -z "$latest_version" || -z "$download_url" ]]; then
    warn 'could not parse version or download URL from API response'
    exit 1
fi

info "latest version: $latest_version"

if [[ "$current_version" == "$latest_version" ]]; then
    info "already up to date ($current_version)"
    if "$SYMLINK" --version >/dev/null 2>&1; then
        info "binary verified OK — ready for use"
    else
        warn "binary check failed"
        exit 1
    fi
    exit 0
fi

info "downloading from: $download_url"

tmp_archive="$(mktemp "${TMPDIR_BASE}/vscode-update-XXXXXX.tar.gz")"
if ! curl -fSL --connect-timeout 30 --max-time 600 -o "$tmp_archive" "$download_url"; then
    rm -f "$tmp_archive"
    printf 'error: download failed\n' >&2
    exit 1
fi

tmp_extract="$(mktemp -d "${TMPDIR_BASE}/vscode-update-XXXXXX")"
if ! tar xzf "$tmp_archive" -C "$tmp_extract"; then
    rm -rf "$tmp_archive" "$tmp_extract"
    printf 'error: extraction failed\n' >&2
    exit 1
fi

# The tarball contains a top-level directory (e.g. VSCode-linux-x64/).
# Find it and rsync its *contents* into the install dir so bin/code lands
# directly at $INSTALL_DIR/bin/code, not nested deeper.
extracted_dir="$(find "$tmp_extract" -maxdepth 1 -type d ! -path "$tmp_extract" | head -1)"
if [[ -z "$extracted_dir" ]]; then
    rm -rf "$tmp_archive" "$tmp_extract"
    printf 'error: no extracted directory found\n' >&2
    exit 1
fi

info "rsyncing from: $extracted_dir/"
rsync -a --delete "$extracted_dir/" "$INSTALL_DIR/"
rm -rf "$tmp_archive" "$tmp_extract"

new_version="$(cat "$INSTALL_DIR/resources/app/package.json" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('version','?'))" 2>/dev/null || echo "?")"
info "installed version: $new_version"

if "$SYMLINK" --version >/dev/null 2>&1; then
    info "binary verified OK — ready for use"
else
    printf 'error: VSCode binary failed verification after update\n' >&2
    exit 1
fi

if [[ -L "$SYMLINK" ]]; then
    info "symlink intact: $SYMLINK -> $(readlink "$SYMLINK")"
else
    mkdir -p "$(dirname "$SYMLINK")"
    ln -sf "$INSTALL_DIR/bin/code" "$SYMLINK"
    info "symlink restored"
fi

info "done"
