#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/apptodate.XXXXXX")"
trap 'rm -rf -- "$LOG_DIR"' EXIT

# Collect all <app>-update.sh scripts (excluding the master harness itself)
UPDATER_SCRIPTS=()
for f in "${SCRIPT_DIR}"/*-update.sh; do
    [[ "$(basename "$f")" == "updater.sh" ]] && continue
    [[ -x "$f" ]] || continue
    UPDATER_SCRIPTS+=("$f")
done

if [[ ${#UPDATER_SCRIPTS[@]} -eq 0 ]]; then
    printf 'error: no updater scripts found in %s\n' "$SCRIPT_DIR" >&2
    exit 1
fi

info() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

info "=========================================="
info "Updater harness — $(date '+%Y-%m-%d %H:%M:%S')"
info "=========================================="
info "scripts found: ${#UPDATER_SCRIPTS[@]}"
for s in "${UPDATER_SCRIPTS[@]}"; do
    info "  - $(basename "$s")"
done
info "=========================================="

success=0
failed=0
failed_names=()
failed_codes=()
failed_logs=()

for i in "${!UPDATER_SCRIPTS[@]}"; do
    script="${UPDATER_SCRIPTS[$i]}"
    name="$(basename "$script")"
    log_file="$LOG_DIR/$i.log"
    printf '\n--- %s ---\n' "$name"

    if "$script" 2>&1 | tee "$log_file"; then
        info "✅ $name completed successfully"
        ((success++)) || true
    else
        code=$?
        info "❌ $name exited with code $code"
        failed_names+=("$name")
        failed_codes+=("$code")
        failed_logs+=("$log_file")
        ((failed++)) || true
    fi
done

printf '\n==========================================\n'
info "Summary: $success succeeded, $failed failed, ${#UPDATER_SCRIPTS[@]} total"
printf '==========================================\n'

if [[ $failed -gt 0 ]]; then
    info ""
    info "Failure details:"
    for i in "${!failed_names[@]}"; do
        printf '\n--- %s (exit code %s) ---\n' "${failed_names[$i]}" "${failed_codes[$i]}"
        cat "${failed_logs[$i]}"
    done
    printf '\n==========================================\n'
    exit 1
fi
