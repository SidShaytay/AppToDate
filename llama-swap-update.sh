#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="llama-swap"
GITHUB_REPO="mostlygeek/llama-swap"
GITHUB_API="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
LLAMA_SWAP_SERVICE="${LLAMA_SWAP_SERVICE:-llama-swap.service}"

info() { printf '%s\n' "$*"; }

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'error: required command not found: %s\n' "$1" >&2
        exit 1
    fi
}

require_command curl
require_command jq
require_command sha256sum
require_command tar
require_command systemctl

command_path="$(command -v llama-swap || true)"
if [[ -z "$command_path" ]]; then
    printf 'error: llama-swap was not found in PATH\n' >&2
    exit 1
fi

if [[ ! -L "$command_path" ]]; then
    printf 'error: expected llama-swap command to be a symlink: %s\n' "$command_path" >&2
    exit 1
fi

install_path="$(readlink -f "$command_path")"
if [[ -z "$install_path" || ! -x "$install_path" ]]; then
    printf 'error: installed llama-swap binary is missing or not executable: %s\n' \
        "${install_path:-unresolved}" >&2
    exit 1
fi

install_dir="$(dirname "$install_path")"
current_output="$("$command_path" --version 2>&1)"
current_version_token="$(printf '%s\n' "$current_output" |
    awk '/^version:/ {print $2; exit}')"
current_version="${current_version_token#v}"

if [[ ! "$current_version" =~ ^[0-9]+$ ]]; then
    printf 'error: could not parse installed llama-swap version from: %s\n' \
        "$current_output" >&2
    exit 1
fi

case "$(uname -m)" in
    x86_64)
        release_arch="amd64"
        ;;
    aarch64)
        release_arch="arm64"
        ;;
    *)
        printf 'error: unsupported architecture: %s\n' "$(uname -m)" >&2
        exit 1
        ;;
esac

info "source: ${GITHUB_REPO} GitHub releases"
info "destination: $install_path"
info "command symlink: $command_path -> $(readlink "$command_path")"
info "current version: $current_version"

latest_release="$(curl -fsSL --connect-timeout 15 --max-time 60 "$GITHUB_API")"
latest_tag="$(printf '%s' "$latest_release" | jq -r '.tag_name // empty')"
latest_version="${latest_tag#v}"

if [[ ! "$latest_version" =~ ^[0-9]+$ ]]; then
    printf 'error: invalid latest release tag from GitHub: %s\n' \
        "${latest_tag:-missing}" >&2
    exit 1
fi

info "latest version: $latest_version"

if (( current_version >= latest_version )); then
    info "$APP_NAME is already up to date"
    "$command_path" --version
    if [[ "$(readlink -f "$command_path")" != "$install_path" ]]; then
        printf 'error: llama-swap symlink target changed during verification\n' >&2
        exit 1
    fi
    info "binary and symlink verified"
    exit 0
fi

asset_name="llama-swap_${latest_version}_linux_${release_arch}.tar.gz"
checksum_name="llama-swap_${latest_version}_checksums.txt"
download_url="$(printf '%s' "$latest_release" | jq -r \
    --arg name "$asset_name" \
    '.assets[] | select(.name == $name) | .browser_download_url' |
    head -n 1)"
checksum_url="$(printf '%s' "$latest_release" | jq -r \
    --arg name "$checksum_name" \
    '.assets[] | select(.name == $name) | .browser_download_url' |
    head -n 1)"

if [[ -z "$download_url" || -z "$checksum_url" ]]; then
    printf 'error: release %s does not contain %s and its checksum manifest\n' \
        "$latest_tag" "$asset_name" >&2
    exit 1
fi

tmp_dir="$(mktemp -d /tmp/llama-swap-update.XXXXXX)"
tmp_install=""
cleanup() {
    rm -rf "$tmp_dir"
    if [[ -n "$tmp_install" ]]; then
        rm -f "$tmp_install"
    fi
}
trap cleanup EXIT

archive_path="${tmp_dir}/${asset_name}"
checksum_path="${tmp_dir}/${checksum_name}"

info "downloading: $download_url"
curl -fL --connect-timeout 30 --max-time 600 -o "$archive_path" "$download_url"
curl -fL --connect-timeout 30 --max-time 60 -o "$checksum_path" "$checksum_url"

expected_checksum="$(awk -v name="$asset_name" '$2 == name {print $1; exit}' \
    "$checksum_path")"
actual_checksum="$(sha256sum "$archive_path" | awk '{print $1}')"
if [[ -z "$expected_checksum" || "$actual_checksum" != "$expected_checksum" ]]; then
    printf 'error: SHA-256 verification failed for %s\n' "$asset_name" >&2
    exit 1
fi
info "SHA-256 verified"

tar -xzf "$archive_path" -C "$tmp_dir"
extracted_binary="$(find "$tmp_dir" -type f -name llama-swap -print -quit)"
if [[ -z "$extracted_binary" ]]; then
    printf 'error: archive did not contain a llama-swap binary\n' >&2
    exit 1
fi

chmod +x "$extracted_binary"
downloaded_output="$("$extracted_binary" --version 2>&1)"
downloaded_version_token="$(printf '%s\n' "$downloaded_output" |
    awk '/^version:/ {print $2; exit}')"
downloaded_version="${downloaded_version_token#v}"
if [[ "$downloaded_version" != "$latest_version" ]]; then
    printf 'error: downloaded binary reports version %s, expected %s\n' \
        "${downloaded_version_token:-unknown}" "$latest_tag" >&2
    exit 1
fi

tmp_install="$(mktemp "${install_dir}/.llama-swap.update.XXXXXX")"
cp "$extracted_binary" "$tmp_install"
chmod 0755 "$tmp_install"
mv -f "$tmp_install" "$install_path"
tmp_install=""

installed_output="$("$command_path" --version 2>&1)"
installed_version_token="$(printf '%s\n' "$installed_output" |
    awk '/^version:/ {print $2; exit}')"
installed_version="${installed_version_token#v}"
if [[ "$installed_version" != "$latest_version" ]]; then
    printf 'error: installed binary reports version %s, expected %s\n' \
        "${installed_version_token:-unknown}" "$latest_tag" >&2
    exit 1
fi
if [[ "$(readlink -f "$command_path")" != "$install_path" ]]; then
    printf 'error: llama-swap symlink was not preserved\n' >&2
    exit 1
fi

info "installed version: $installed_version"
info "binary and symlink verified"
info "restarting $LLAMA_SWAP_SERVICE"
systemctl --user restart "$LLAMA_SWAP_SERVICE"
if ! systemctl --user is-active --quiet "$LLAMA_SWAP_SERVICE"; then
    printf 'error: %s is not active after restart\n' "$LLAMA_SWAP_SERVICE" >&2
    exit 1
fi

info "$LLAMA_SWAP_SERVICE is active"
info "done"
