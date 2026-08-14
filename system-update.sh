#!/usr/bin/env bash
set -Eeuo pipefail

RPM_OSTREE="${RPM_OSTREE:-rpm-ostree}"
JQ="${JQ:-jq}"
SUDO_ASKPASS_HELPER="${SUDO_ASKPASS_HELPER:-${HOME}/.local/bin/sudo-askpass-smart}"

info() { printf '%s\n' "$*"; }

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'error: required command not found: %s\n' "$1" >&2
        exit 1
    fi
}

ensure_sudo() {
    if sudo -n true 2>/dev/null; then
        return
    fi

    if [[ ! -x "$SUDO_ASKPASS_HELPER" ]]; then
        printf 'error: sudo credentials are required and askpass helper is unavailable: %s\n' \
            "$SUDO_ASKPASS_HELPER" >&2
        printf 'Run "sudo -v" in a separate interactive shell, then retry.\n' >&2
        exit 1
    fi

    if ! SUDO_ASKPASS="$SUDO_ASKPASS_HELPER" sudo -A -v; then
        printf 'error: could not acquire sudo credentials through the local askpass helper\n' >&2
        printf 'Run "sudo -v" in a separate interactive shell, then retry.\n' >&2
        exit 1
    fi

    if ! sudo -n true; then
        printf 'error: sudo credentials were not cached after authentication\n' >&2
        exit 1
    fi
}

require_command "$RPM_OSTREE"
require_command "$JQ"
require_command sudo

status_json="$("$RPM_OSTREE" status --json)"
booted_json="$(printf '%s' "$status_json" | "$JQ" -c \
    '[.deployments[] | select(.booted == true)][0]')"

if [[ "$booted_json" == "null" ]]; then
    printf 'error: rpm-ostree did not report a booted deployment\n' >&2
    exit 1
fi

origin="$(printf '%s' "$booted_json" | "$JQ" -r '.origin')"
current_version="$(printf '%s' "$booted_json" | "$JQ" -r '.version')"
current_checksum="$(printf '%s' "$booted_json" | "$JQ" -r '.checksum')"

info "source: $origin"
info "destination: / (next boot deployment)"
info "current version: $current_version"
info "current checksum: $current_checksum"
info "checking for Fedora system updates"

set +e
check_output="$("$RPM_OSTREE" update --check 2>&1)"
check_status=$?
set -e
printf '%s\n' "$check_output"

if [[ $check_status -eq 77 ]]; then
    info "system is already up to date"
    exit 0
elif [[ $check_status -ne 0 ]]; then
    printf 'error: rpm-ostree update check exited with code %d\n' "$check_status" >&2
    exit "$check_status"
fi

ensure_sudo

info "staging system update"
set +e
update_output="$(sudo -n "$RPM_OSTREE" update --unchanged-exit-77 2>&1)"
update_status=$?
set -e
printf '%s\n' "$update_output"

if [[ $update_status -eq 77 ]]; then
    info "system became up to date before staging; nothing to do"
    exit 0
elif [[ $update_status -ne 0 ]]; then
    printf 'error: rpm-ostree update exited with code %d\n' "$update_status" >&2
    exit "$update_status"
fi

updated_status_json="$("$RPM_OSTREE" status --json)"
staged_json="$(printf '%s' "$updated_status_json" | "$JQ" -c \
    '[.deployments[] | select(.staged == true)][0]')"

if [[ "$staged_json" == "null" ]]; then
    printf 'error: update completed but no staged deployment was found\n' >&2
    exit 1
fi

staged_version="$(printf '%s' "$staged_json" | "$JQ" -r '.version')"
staged_checksum="$(printf '%s' "$staged_json" | "$JQ" -r '.checksum')"

if [[ -z "$staged_checksum" || "$staged_checksum" == "null" ]]; then
    printf 'error: staged deployment has no checksum\n' >&2
    exit 1
fi

info "staged version: $staged_version"
info "staged checksum: $staged_checksum"
info "system update verified; reboot when convenient to activate it"
