#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="Podman images"

info() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

# Check podman is available
if ! command -v podman >/dev/null 2>&1; then
    printf 'error: podman not found\n' >&2
    exit 1
fi

# List of custom images to update (non-system, user-pulled)
IMAGES=(
    "ghcr.io/gethomepage/homepage:latest"
    "registry.fedoraproject.org/fedora-toolbox:44"
    "ghcr.io/open-webui/open-webui:latest"
    "ghcr.io/sidshaytay/rocm-toolbox:7.2.3"
    "ghcr.io/sillytavern/sillytavern:latest"
    "docker.io/library/traefik:v3.3"
)

info "updating $APP_NAME"
info "images to update:"
for img in "${IMAGES[@]}"; do
    info "  $img"
done

pulled=0
skipped=0
failed=0

# Map image names to systemd services to restart after pull
declare -A IMAGE_SERVICE=(
    ["ghcr.io/gethomepage/homepage:latest"]="homepage.service"
    ["ghcr.io/open-webui/open-webui:latest"]="open-webui.service"
    ["ghcr.io/sidshaytay/rocm-toolbox:7.2.3"]="sillytavern.service"
    ["docker.io/library/traefik:v3.3"]="traefik.service"
)

for img in "${IMAGES[@]}"; do
    if [[ "$img" == *":"* ]]; then
        printf 'pulling %s\n' "$img" >&2
        if podman pull "$img" 2>&1; then
            ((pulled++)) || true
            # Restart associated service if any
            svc="${IMAGE_SERVICE[$img]:-}"
            if [[ -n "$svc" ]]; then
                info "restarting $svc after image update"
                systemctl --user restart "$svc" 2>/dev/null || warn "failed to restart $svc"
            fi
        else
            printf 'warning: failed to pull %s\n' "$img" >&2
            ((failed++)) || true
        fi
    else
        printf 'skipping %s (no tag)\n' "$img" >&2
        ((skipped++)) || true
    fi
done

info "pulled: $pulled, skipped: $skipped, failed: $failed"
info "done"
