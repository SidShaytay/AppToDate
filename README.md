# AppToDate

AppToDate keeps applications and system components up to date when they are not fully managed by one package manager. It is designed for a Fedora Silverblue workstation and provides small, auditable Bash scripts for each update source. This is opinionated on how one sets up their Apps (e.g. some as brew, some as flatpaks etc.)

## Quick start

Clone the repository and run the master updater:

```bash
git clone git@github.com:SidShaytay/AppToDate.git
cd AppToDate
./updater.sh
```

The harness discovers every executable `*-update.sh` file, runs them one at a time, and prints a final success/failure summary. You can also run one updater directly:

```bash
./vscode-update.sh
```

Review each script before running it. These scripts reflect a specific workstation layout and can replace application binaries, update containers, restart user services, or stage an operating-system deployment.

## Included updaters

| Script | Updates | Method |
| --- | --- | --- |
| `brew-update.sh` | Homebrew and installed formulae/casks | `brew update` and `brew upgrade --greedy` |
| `cargo-update.sh` | Rust/Cargo and Cargo-installed binaries | `rustup update` and `cargo-update`, using `cargo-binstall` for prebuilt binaries |
| `flatpak-update.sh` | Flatpak applications | `flatpak update` |
| `podman-update.sh` | Selected Podman images | Pulls configured images and restarts associated user services |
| `vscode-update.sh` | Visual Studio Code tarball install | Downloads and replaces the local installation |
| `onedrivegui-update.sh` | OneDriveGUI AppImage | Downloads the latest GitHub release |
| `lmstudio-update.sh` | LM Studio AppImage | Follows the current LM Studio download redirect |
| `llama.cpp-update.sh` | Local llama.cpp build | Fast-forwards source, builds with ROCm in Toolbox, and syncs binaries |
| `llama-swap-update.sh` | llama-swap | Downloads a release, verifies its checksum, and replaces the binary |
| `system-update.sh` | Fedora Silverblue | Checks and stages an `rpm-ostree` deployment for the next boot |

## Requirements

- Fedora Silverblue with Fish or Bash shell
- The command-line tools used by the updater you run, such as `curl`, `jq`, `podman`, `flatpak`, `toolbox`, `rsync`, or `rpm-ostree`
- Existing application installs in the paths defined near the top of each script
- User-level systemd services matching the configured service names

`system-update.sh` checks for cached non-interactive sudo access first. If needed, it can use a local askpass helper at `$HOME/.local/bin/sudo-askpass-smart`; override `SUDO_ASKPASS_HELPER` to use another helper.

Run `./cargo-update.sh` to update Rust release channels and installed Cargo binaries. It installs `cargo-binstall` and `cargo-update` automatically if missing, skips unchanged versions, and verifies that installed executable files remain present. Prebuilt packages come from upstream releases or Cargo QuickInstall; source compilation fallback in `cargo-binstall` is disabled. Git packages and packages with custom build settings still need a working compiler and native dependencies. Update failures are reported to the harness.

Version-pinned Rust toolchains and your default selection are preserved. The script also updates `stable`; use `cargo +stable` for its current Cargo, or run `rustup default stable` if you want your default Cargo to follow stable releases. `CARGO_HOME`, `RUSTUP_HOME`, and `CARGO_INSTALL_ROOT` can override the standard paths. No services are restarted.

## Customize it

Each updater keeps its application paths, image list, and service names near the top of the file. Adjust those values for your workstation before running it. Some settings, including `LLAMA_SWAP_SERVICE`, `TOOLBOX_CONTAINER`, and `SUDO_ASKPASS_HELPER`, can also be supplied as environment variables.

To add another updater, create an executable script named `<app>-update.sh`. The master harness will discover it automatically.
