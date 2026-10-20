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
    ["ghcr.io/sillytavern/sillytavern:latest"]="sillytavern.service"
    ["docker.io/library/traefik:v3.3"]="traefik.service"
)

# Require the new image and three consecutive successful checks. Images without
# health checks must stay running; images with checks must also report healthy.
verify_container() {
    local svc="$1" container="$2" expected="$3"
    local state image running health attempt stable=0
    for ((attempt=0; attempt<60; attempt++)); do
        if systemctl --user is-active --quiet "$svc" &&
           state=$(podman container inspect --format \
               '{{.Image}} {{.State.Running}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
               "$container" 2>/dev/null); then
            read -r image running health <<< "$state"
            if [[ "$image" == "$expected" && "$running" == true &&
                  ( "$health" == healthy || "$health" == none ) ]]; then
                stable=$((stable + 1))
                if ((stable >= 3)); then return 0; fi
            else
                stable=0
            fi
        else
            stable=0
        fi
        sleep 2
    done
    return 1
}

cleanup_image() {
    local old_image="$1" users
    # Include stopped containers. Never force removal or prune unrelated images.
    if ! users=$(podman ps -a --filter "ancestor=$old_image" --format '{{.ID}}'); then
        warn "cannot check users of $old_image; keeping image"
    elif [[ -n "$users" ]]; then
        info "keeping $old_image: still referenced by a container"
    else
        info "removing replaced image $old_image"
        podman image rm --no-prune "$old_image" || warn "could not remove $old_image"
    fi
}

for img in "${IMAGES[@]}"; do
    if [[ "$img" == *":"* ]]; then
        old_image=$(podman image inspect --format '{{.Id}}' "$img" 2>/dev/null) || old_image=""
        info "source: $img; destination: local Podman storage; current: ${old_image:-not installed}"
        printf 'pulling %s\n' "$img" >&2
        if podman pull "$img" 2>&1; then
            ((pulled++)) || true
            if ! new_image=$(podman image inspect --format '{{.Id}}' "$img"); then
                warn "cannot inspect pulled image $img; keeping old image"
                ((failed++)) || true
                continue
            fi
            if [[ "$old_image" == "$new_image" ]]; then
                info "$img is already up to date"
                ((skipped++)) || true
                continue
            fi
            svc="${IMAGE_SERVICE[$img]:-}"
            if [[ -n "$svc" ]]; then
                info "restarting $svc after image update"
                if ! systemctl --user restart "$svc"; then
                    warn "failed to restart $svc; keeping old image"
                    ((failed++)) || true
                    continue
                fi
                if ! verify_container "$svc" "${svc%.service}" "$new_image"; then
                    warn "$svc did not become ready on the new image; keeping old image"
                    ((failed++)) || true
                    continue
                fi
                info "$svc verified on $new_image"
                if [[ -n "$old_image" ]]; then cleanup_image "$old_image"; fi
            else
                info "no managed service for $img; keeping old image"
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
