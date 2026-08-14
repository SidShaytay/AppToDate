#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
skipped=0

for script in "${UPDATER_SCRIPTS[@]}"; do
    name="$(basename "$script")"
    printf '\n--- %s ---\n' "$name"

    if "$script" 2>&1; then
        info "✅ $name completed successfully"
        ((success++)) || true
    else
        code=$?
        info "❌ $name exited with code $code"
        ((failed++)) || true
    fi
done

printf '\n==========================================\n'
info "Summary: $success succeeded, $failed failed, ${#UPDATER_SCRIPTS[@]} total"
printf '==========================================\n'

if [[ $failed -gt 0 ]]; then
    exit 1
fi
