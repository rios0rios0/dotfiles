# shellcheck shell=bash
# Shared dependency-installation library included by the Linux/WSL and Android
# dependency installers through a chezmoi `template` directive. Files under
# `.chezmoitemplates/` are themselves parsed as templates, so this file must
# never contain the Go template action delimiter (two opening curly braces),
# not even inside a comment: spelling out its own include recursed until
# chezmoi aborted on the template depth limit.
#
# Only functions whose body is correct on both platforms without a conditional
# live here. Tools that are provisioned differently -- apt repositories versus
# binary downloads (`gh`, `kubectl`), upstream install scripts versus source
# builds (`terra`, `dev-toolkit`, `aisync`), pyenv versus Termux's native
# Python -- stay in the platform installers. The file is pure bash (no template
# directives) so `make lint-shellcheck` lints it as a plain `.sh` file.
#
# Every function is idempotent: chezmoi re-runs a `run_once_` script whenever
# its rendered content changes, so a re-run on a provisioned machine must be
# cheap. See `.docs/dependency-lifecycle.md` for the removal half.

# =========================================================================================================
command_exists() {
    local name="$1"
    command -v "$name" >/dev/null 2>&1 || return 1
    return 0
}

# Download an installer script over HTTPS and run it with bash, forwarding any
# further arguments to the script. Piping curl straight into bash, or running
# `sh -c` on a command substitution, would hide a failed download: an HTTP
# error page reaches the shell, or an empty string runs as a no-op that exits
# 0, and these installers do not enable `pipefail`. Downloading to a file first
# makes the download status explicit and fails fast.
run_remote_installer() {
    local name="$1"
    local url="$2"
    shift 2
    local installer
    local status

    installer="$(mktemp)"
    if ! curl --proto '=https' -fsSL "$url" -o "$installer"; then
        echo "[install-deps] ERROR: failed to download the $name installer from $url" >&2
        rm -f "$installer"
        return 1
    fi

    bash "$installer" "$@"
    status=$?
    rm -f "$installer"
    if [[ "$status" -ne 0 ]]; then
        echo "[install-deps] ERROR: the $name installer exited with status $status" >&2
    fi
    return "$status"
}

# https://ohmyz.sh/#install
install_oh_my_zsh() {
    if [[ -d "${ZSH:-$HOME/.oh-my-zsh}" ]]; then
        echo "[install-deps] oh-my-zsh is already installed, skipping" >&2
        return
    fi

    # `--unattended` stops the installer from prompting for `chsh` and from
    # `exec`-ing a login zsh in the middle of an unattended run. Each platform
    # installer switches the login shell itself right after this call, and only
    # when this call succeeded (`usermod` on Linux, Termux's `chsh -s zsh` on
    # Android).
    run_remote_installer "Oh My Zsh" "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh" --unattended || return 1
}

# https://sdkman.io/install/
install_sdkman() {
    if [[ -d "$HOME/.sdkman" ]]; then
        echo "[install-deps] SDKMAN is already installed, skipping download" >&2
    else
        run_remote_installer "SDKMAN" "https://get.sdkman.io" || return 1
    fi

    # Source SDKMAN to make it available in the current shell
    export SDKMAN_DIR="$HOME/.sdkman"
    # shellcheck source=/dev/null
    [[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"

    # SDKMAN writes download headers/post-install hooks to `$SDKMAN_DIR/tmp`
    # before running curl. The directory occasionally goes missing (e.g. after
    # a manual cleanup) and `sdk install` fails with
    # "curl: Failed to open .../*.headers.tmp". Recreate it defensively.
    mkdir -p "$SDKMAN_DIR/tmp"

    # Keep SDKMAN itself up to date so candidate metadata (new Java/Gradle
    # versions, broker URLs) refreshes on every apply.
    sdk selfupdate force >/dev/null 2>&1 || echo "[install-deps] WARN: sdk selfupdate failed; continuing" >&2

    sdk install java
    sdk install gradle
}

# https://github.com/nvm-sh/nvm?tab=readme-ov-file#install--update-script
install_nvm() {
    # Termux ships Node.js as a native package (`nodejs` in the Android
    # installer's `languages` array) and NVM's Linux builds do not run there,
    # so on Termux an existing `npm` only gets corepack. The branch is gated on
    # Termux's prefix rather than on where `npm` resolves from: WSL exposes
    # Windows' `npm` through PATH interop, which must not disable NVM on Linux.
    if [[ -d /data/data/com.termux/files/usr ]] && command_exists npm; then
        echo "[install-deps] Termux native Node.js detected, skipping NVM" >&2
        npm install -g --ignore-scripts corepack
        corepack enable
        return
    fi

    if [[ ! -d "$HOME/.nvm" ]]; then
        run_remote_installer "NVM" "https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.2/install.sh" || return 1
    else
        echo "[install-deps] NVM is already installed, skipping download" >&2
    fi

    # NVM refuses to run while `PREFIX` is set (Termux exports it globally);
    # a no-op everywhere else.
    unset PREFIX

    # Source NVM to make it available in the current shell
    export NVM_DIR="$HOME/.nvm"
    # shellcheck source=/dev/null
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"

    local lts_version
    lts_version="$(nvm version-remote --lts 2>/dev/null)" || true
    local current_version
    current_version="$(nvm current 2>/dev/null)" || true

    if [[ -n "$lts_version" && "$current_version" == "$lts_version" ]]; then
        echo "[install-deps] Node.js LTS $lts_version is already installed, skipping" >&2
    else
        # Globally installed npm packages live inside the active version's tree, so a
        # new LTS major starts empty and every `npm install -g` CLI this installer
        # placed (`codex`, `sentry`, Claude Code) silently disappears from PATH -- the
        # old tree still holds them, which is why nothing downstream reports an error.
        # `--reinstall-packages-from` rebuilds them in the new tree. It is only passed
        # when there is a version to copy from: on a first install `nvm current` prints
        # `none`/`system`, and nvm aborts the whole install on such a source.
        local -a reinstall_from=()
        if [[ "$current_version" =~ ^v[0-9] ]]; then
            reinstall_from=(--reinstall-packages-from="$current_version")
        fi
        nvm install --lts "${reinstall_from[@]}"
    fi

    # corepack ships no lifecycle scripts, so `--ignore-scripts` costs nothing and
    # keeps a compromised registry response from running code at install time.
    npm install -g --ignore-scripts corepack
    corepack enable
}
# =========================================================================================================

# =========================================================================================================
# https://fly.io/docs/flyctl/install/
# Same body on both platforms: the upstream installer drops the release binary under
# ~/.fly/bin. `--non-interactive` without `--setup-path` keeps the installer out of the
# shell rc files, which chezmoi owns. What differs per platform lives elsewhere: on Linux
# `dot_zshenv.tmpl` puts ~/.fly/bin on PATH; on Termux the static linux/arm64 build starts
# but resolves nothing (Go's resolver reads /etc/resolv.conf, which Android does not have,
# and falls back to [::1]:53), so `run_after_android-003-wrap-terra-clis.sh` fronts it with
# a termux-etc-seccomp wrapper in ~/.local/bin and ~/.fly/bin stays off PATH there.
install_fly_cli() {
    if [[ -x "$HOME/.fly/bin/flyctl" ]]; then
        echo "[install-deps] flyctl is already installed, skipping" >&2
        return
    fi

    FLYCTL_INSTALL="$HOME/.fly" run_remote_installer "flyctl" "https://fly.io/install.sh" --non-interactive || return 1
}

# =========================================================================================================
# https://cli.sentry.dev/getting-started/
# Sentry CLI (binary `sentry`, npm package `sentry`, from getsentry/cli -- not the classic
# Rust `sentry-cli`). Same body on both platforms because the npm package is the CLI itself
# as a plain JavaScript bundle: no platform-specific optional dependency, no lifecycle
# script, `engines.node >= 20` (22.15+ uses the built-in `node:sqlite` for ~/.sentry/cli.db,
# older Node falls back to a bundled WASM driver). The official install script
# (`curl https://cli.sentry.dev/install | bash`) is deliberately NOT used: it downloads the
# Bun-compiled `sentry-linux-<arch>` executable, a glibc binary -- the `-musl` variants
# stopped shipping after 0.34.0 -- and on Termux the kernel cannot even start it
# (`/lib/ld-linux-aarch64.so.1` does not exist under bionic), so it dies before
# `sentry cli setup`. Under Termux's native Node the bundle needs no termux-etc-redirect
# wrapper either: DNS and TLS go through bionic, which is what a `sentry cli upgrade --check`
# round trip verified on a device. `sentry cli upgrade` recognises the npm layout from its
# own path and upgrades through npm. Completions and the agent skill are not part of an npm
# install; `run_onchange_after_<platform>-*-setup-sentry-cli.sh` runs `sentry cli setup
# --no-modify-path` for them once the managed files -- including the fpath line in ~/.zshrc
# that command checks for -- are in place.
install_sentry_cli() {
    if command_exists sentry; then
        echo "[install-deps] Sentry CLI is already installed, skipping" >&2
        return
    fi

    if ! command_exists npm || ! command_exists node; then
        echo "[install-deps] ERROR: npm is not available; install_nvm must run before install_sentry_cli" >&2
        return 1
    fi

    # The package declares `engines.node >= 20`; skip early instead of installing a
    # launcher that fails on every run. Both skips are deliberate best-effort outcomes,
    # so they return success like the Android copilot install does -- only a failed
    # install is reported as a failure.
    local node_major
    node_major="$(node --version 2>/dev/null | sed -E 's/^v([0-9]+).*/\1/')"
    if [[ ! "$node_major" =~ ^[0-9]+$ ]]; then
        echo "[install-deps] WARN: could not determine the Node.js version, skipping the Sentry CLI" >&2
        return 0
    fi
    if [[ "$node_major" -lt 20 ]]; then
        echo "[install-deps] WARN: the Sentry CLI needs Node.js 20+, found v$node_major; skipping" >&2
        return 0
    fi

    # The package ships no lifecycle scripts, so `--ignore-scripts` costs nothing and keeps a
    # compromised registry response from running code at install time (as for corepack).
    if ! npm install -g --ignore-scripts sentry; then
        echo "[install-deps] ERROR: npm install -g sentry failed" >&2
        return 1
    fi

    if ! command_exists sentry; then
        echo "[install-deps] WARN: the Sentry CLI was installed but 'sentry' is not on PATH; check 'npm prefix -g'" >&2
    fi
}
