#!/usr/bin/env bash
set -Eeuo pipefail

SRC_DIR="${HOME}/Projects/ai/llama.cpp"
DEST_ROOT="/var/mnt/data/projects/ai/llama.cpp"
BUILD_DIR="${DEST_ROOT}/build-rocm-7.2.3"
APP_DIR="${HOME}/Apps/llama.cpp"
TOOLBOX_CONTAINER="${TOOLBOX_CONTAINER:-rocm-7.2.3}"
LLAMA_SWAP_SERVICE="${LLAMA_SWAP_SERVICE:-llama-swap.service}"

info() {
    printf '%s\n' "$*"
}

require_dir() {
    if [[ ! -d "$1" ]]; then
        printf 'error: required directory does not exist: %s\n' "$1" >&2
        exit 1
    fi
}

require_dir "$SRC_DIR"
require_dir "$DEST_ROOT"
require_dir "$APP_DIR"

resolved_dest="$(readlink -f "$DEST_ROOT")"
if [[ "$resolved_dest" != "/var/mnt/data/projects/ai/llama.cpp" ]]; then
    printf 'error: destination resolved unexpectedly: %s\n' "$resolved_dest" >&2
    exit 1
fi

resolved_app="$(readlink -f "$APP_DIR")"
if [[ "$resolved_app" != "$(readlink -f "${HOME}/Apps/llama.cpp")" ]]; then
    printf 'error: app install directory resolved unexpectedly: %s\n' "$resolved_app" >&2
    exit 1
fi

if ! git -C "$SRC_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'error: source is not a git checkout: %s\n' "$SRC_DIR" >&2
    exit 1
fi

branch="$(git -C "$SRC_DIR" branch --show-current || true)"
old_rev="$(git -C "$SRC_DIR" rev-parse HEAD)"

info "source: origin/master ($SRC_DIR)"
info "destination: $APP_DIR"
info "current source revision: $old_rev"

if [[ "$branch" != "master" ]]; then
    printf "error: source branch is '%s'; expected 'master'\n" \
        "${branch:-detached HEAD}" >&2
    exit 1
fi

if ! git -C "$SRC_DIR" diff --quiet ||
    ! git -C "$SRC_DIR" diff --cached --quiet; then
    printf 'error: source checkout has modified tracked files; refusing to pull\n' >&2
    exit 1
fi

info "pulling latest llama.cpp master"
git -C "$SRC_DIR" pull --ff-only origin master
new_rev="$(git -C "$SRC_DIR" rev-parse HEAD)"

if [[ "$old_rev" == "$new_rev" ]]; then
    info "source is already up to date: $new_rev"
else
    info "source updated: $old_rev -> $new_rev"
fi

info "building llama.cpp from $SRC_DIR"
info "build output root: $BUILD_DIR"
info "toolbox container: $TOOLBOX_CONTAINER"

mkdir -p "$BUILD_DIR"

toolbox run -c "$TOOLBOX_CONTAINER" \
    env SRC_DIR="$SRC_DIR" BUILD_DIR="$BUILD_DIR" \
    bash -lc '
        set -Eeuo pipefail
        cd "$SRC_DIR"
        export HIPCXX="$(hipconfig -l)/clang"
        export HIP_PATH="$(hipconfig -R)"
        cmake --fresh -S "$SRC_DIR" -B "$BUILD_DIR" \
            -DGGML_HIP=ON \
            -DCMAKE_BUILD_TYPE=Release \
            -DBUILD_SHARED_LIBS=ON
        cmake --build "$BUILD_DIR" --config Release --parallel "$(nproc)"
    '

info "built llama-server:"
toolbox run -c "$TOOLBOX_CONTAINER" "$BUILD_DIR/bin/llama-server" --version

if [[ ! -x "$BUILD_DIR/bin/llama-server" ]]; then
    printf 'error: expected built llama-server missing: %s\n' "$BUILD_DIR/bin/llama-server" >&2
    exit 1
fi

info "syncing build output into $APP_DIR for llama-swap"
# This app directory is a generated flat copy of build/bin. Keep updater
# scripts outside it so --delete can remove stale binaries and libraries.
rsync -a --delete "$BUILD_DIR/bin/" "$APP_DIR/"

info "installed llama-server:"
toolbox run -c "$TOOLBOX_CONTAINER" "$APP_DIR/llama-server" --version

info "restarting $LLAMA_SWAP_SERVICE"
systemctl --user restart "$LLAMA_SWAP_SERVICE"

info "done"
