#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="LM Studio"
APPIMAGE="${HOME}/Apps/lm_studio.appimage"
DOWNLOAD_BASE="https://lmstudio.ai/download/latest/linux/x64?format=AppImage"

info() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

# Check current AppImage exists
if [[ ! -x "$APPIMAGE" ]]; then
    printf 'error: AppImage not found or not executable: %s\n' "$APPIMAGE" >&2
    exit 1
fi

# Get current version from X-AppImage-Version in desktop file
desktop_file="${HOME}/.local/share/applications/lm_studio.desktop"
if [[ -f "$desktop_file" ]]; then
    current_version="$(grep '^X-AppImage-Version=' "$desktop_file" | cut -d= -f2 || echo "?")"
else
    current_version="?"
fi
version_file="${APPIMAGE}.version"
if [[ -s "$version_file" ]]; then
    current_version="$(<"$version_file")"
fi
info "source: $DOWNLOAD_BASE"
info "destination: $APPIMAGE"
info "updating $APP_NAME"
info "installed version: $current_version"

# Resolve the latest download URL (redirects to actual CDN)
download_url="$(curl -fsS --head -L --connect-timeout 15 --max-time 60 -o /dev/null -w '%{url_effective}' "$DOWNLOAD_BASE" 2>/dev/null || echo "")"

if [[ -z "$download_url" ]]; then
    warn 'could not resolve download URL from LM Studio API'
    exit 1
fi

info "latest version URL: $download_url"

latest_version="$(printf '%s\n' "$download_url" | grep -oP '[\d]+\.[\d]+\.[\d]+(-[\d]+)?' | head -1 || true)"
if [[ -z "$latest_version" ]]; then
    warn 'could not parse latest version from download URL'
    exit 1
fi
current_normalized="${current_version#v}"
if [[ "$current_normalized" == "$latest_version" ]] ||
   { [[ "$current_normalized" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?$ ]] &&
     [[ "$(printf '%s\n' "$current_normalized" "$latest_version" | sort -V | head -n 1)" == "$latest_version" ]]; }; then
    info "$APP_NAME is already up to date; skipping download"
    exit 0
fi

# Download to a temp file, then replace
tmp_appimage="$(mktemp "${APPIMAGE%.appimage}.XXXXXX.AppImage")"
if ! curl -fSL --connect-timeout 30 --max-time 600 -o "$tmp_appimage" "$download_url"; then
    rm -f "$tmp_appimage"
    printf 'error: download failed\n' >&2
    exit 1
fi

chmod +x "$tmp_appimage"

# Atomic replace
mv -f "$tmp_appimage" "$APPIMAGE"
printf '%s\n' "$latest_version" > "$version_file"

# Update desktop file version if present (extract version from URL)
if [[ -f "$desktop_file" ]]; then
    # Extract version from URL like: .../0.4.13-1/LM-Studio-0.4.13-1-x64.AppImage
    extracted_version="$(echo "$download_url" | grep -oP '[\d]+\.[\d]+\.[\d]+(-[\d]+)?' | head -1 || echo "")"
    if [[ -n "$extracted_version" ]]; then
        sed -i "s/^X-AppImage-Version=.*/X-AppImage-Version=${extracted_version}/" "$desktop_file"
        info "updated desktop file version: $extracted_version"
    fi
fi

info "done"
