#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="OneDriveGUI"
APPIMAGE="${HOME}/Apps/onedrivegui.appimage"
GITHUB_REPO="bpozdena/OneDriveGUI"

info() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

# Check current AppImage exists
if [[ ! -x "$APPIMAGE" ]]; then
    printf 'error: AppImage not found or not executable: %s\n' "$APPIMAGE" >&2
    exit 1
fi

# Get current version from X-AppImage-Version in desktop file or the binary itself
desktop_file="${HOME}/.local/share/applications/onedrivegui.desktop"
if [[ -f "$desktop_file" ]]; then
    current_version="$(grep '^X-AppImage-Version=' "$desktop_file" | cut -d= -f2 || echo "?")"
else
    current_version="?"
fi
# Preserve version knowledge even when no desktop integration is installed.
version_file="${APPIMAGE}.version"
if [[ -s "$version_file" ]]; then
    current_version="$(<"$version_file")"
fi
info "source: ${GITHUB_REPO} GitHub releases"
info "destination: $APPIMAGE"
info "updating $APP_NAME"
info "installed version: $current_version"

# Get latest release from GitHub API
latest_release="$(curl -sS --connect-timeout 15 "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null || echo "")"

if [[ -z "$latest_release" ]]; then
    warn 'could not query GitHub releases API'
    exit 1
fi

latest_tag="$(echo "$latest_release" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name',''))" 2>/dev/null || echo "")"
if [[ -z "$latest_tag" ]]; then
    warn 'could not parse latest tag from GitHub API'
    exit 1
fi

info "latest version: $latest_tag"
current_normalized="${current_version#v}"
latest_normalized="${latest_tag#v}"
if [[ "$current_normalized" == "$latest_normalized" ]] ||
   { [[ "$current_normalized" =~ ^[0-9]+(\.[0-9]+)*$ &&
        "$latest_normalized" =~ ^[0-9]+(\.[0-9]+)*$ ]] &&
     [[ "$(printf '%s\n' "$current_normalized" "$latest_normalized" | sort -V | head -n 1)" == "$latest_normalized" ]]; }; then
    info "$APP_NAME is already up to date; skipping download"
    exit 0
fi

# Extract download URL for x86_64 AppImage
download_url="$(echo "$latest_release" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for a in d.get('assets', []):
    if 'x86_64' in a['name'] and 'AppImage' in a['name']:
        print(a['browser_download_url'])
        break
" 2>/dev/null || echo "")"

if [[ -z "$download_url" ]]; then
    warn 'no x86_64 AppImage asset found in latest release'
    exit 1
fi

info "latest version: $latest_tag"
info "downloading from: $download_url"

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
printf '%s\n' "$latest_tag" > "$version_file"

# Update desktop file version if present
if [[ -f "$desktop_file" ]]; then
    sed -i "s/^X-AppImage-Version=.*/X-AppImage-Version=${latest_tag}/" "$desktop_file"
fi

info "installed version: $latest_tag"
info "done"
