#!/usr/bin/env bash
set -Eeuo pipefail

CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
INSTALL_ROOT="${CARGO_INSTALL_ROOT:-$CARGO_HOME}"
export CARGO_HOME RUSTUP_HOME
export PATH="$CARGO_HOME/bin:$INSTALL_ROOT/bin:$PATH"

info() { printf '%s\n' "$*"; }

for tool in rustup cargo curl tar; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'error: required command not found: %s\n' "$tool" >&2
        exit 1
    fi
done

info 'updating Cargo, Rust toolchains, and Cargo-installed binaries'
info 'source: Rust release channels, Cargo registries, and installed Git sources'
info "destination: $RUSTUP_HOME and $INSTALL_ROOT/bin"
info "current version: $(cargo --version)"
info "active toolchain: $(rustup show active-toolchain)"
info 'installed binaries (before):'
cargo install --list --root "$INSTALL_ROOT"

# Version-pinned toolchains stay pinned. rustup skips unchanged releases.
rustup update
# Use current stable for builds even when the user's default is version-pinned.
rustup update stable --no-self-update
info "build toolchain: $(cargo +stable --version)"
# Bootstrap from the official release, then register it in Cargo's metadata.
export BINSTALL_DISABLE_STRATEGIES=compile
export BINSTALL_NO_CONFIRM=true
if [[ ! -x "$INSTALL_ROOT/bin/cargo-binstall" ]]; then
    case "$(uname -m)" in
        x86_64|aarch64) target="$(uname -m)-unknown-linux-musl" ;;
        *) printf 'error: unsupported cargo-binstall bootstrap architecture\n' >&2; exit 1 ;;
    esac
    temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/cargo-updater.XXXXXX")"
    trap 'rm -rf -- "$temp_dir"' EXIT
    curl -fL --retry 3 -o "$temp_dir/binstall.tgz" \
        "https://github.com/cargo-bins/cargo-binstall/releases/latest/download/cargo-binstall-$target.tgz"
    tar -xzf "$temp_dir/binstall.tgz" -C "$temp_dir" cargo-binstall
    "$temp_dir/cargo-binstall" binstall --root "$INSTALL_ROOT" cargo-binstall
fi
if [[ ! -x "$INSTALL_ROOT/bin/cargo-install-update" ]]; then
    cargo binstall --root "$INSTALL_ROOT" cargo-update
fi
# cargo-update compares versions first, then uses binstall for eligible crates.
# Git installs and crates with custom build settings still require a compiler.
cargo +stable install-update --all --git --locked --root "$INSTALL_ROOT"

info 'verifying Cargo and installed executable files'
cargo --version
cargo +stable --version
installed="$(cargo install --list --root "$INSTALL_ROOT")"
printf '%s\n' "$installed"
while IFS= read -r line; do
    if [[ "$line" == '    '* ]]; then
        binary="${line#    }"
        if [[ ! -x "$INSTALL_ROOT/bin/$binary" ]]; then
            printf 'error: installed binary missing or not executable: %s\n' "$binary" >&2
            exit 1
        fi
    fi
done <<< "$installed"
"$INSTALL_ROOT/bin/cargo-install-update" --version
info 'done (version-pinned toolchains and default toolchain selection are preserved)'
