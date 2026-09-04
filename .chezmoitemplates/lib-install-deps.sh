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

# https://ohmyz.sh/#install
install_oh_my_zsh() {
    if [[ -d "${ZSH:-$HOME/.oh-my-zsh}" ]]; then
        echo "[install-deps] oh-my-zsh is already installed, skipping" >&2
        return
    fi

    # `--unattended` stops the installer from prompting for `chsh` and from
    # `exec`-ing a login zsh in the middle of an unattended run. Each platform
    # installer switches the login shell itself right after this call
    # (`usermod` on Linux, Termux's `chsh -s zsh` on Android).
    # `--proto '=https'` keeps a redirect from downgrading the download to plain HTTP.
    sh -c "$(curl --proto '=https' -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
}

# https://sdkman.io/install/
install_sdkman() {
    if [[ -d "$HOME/.sdkman" ]]; then
        echo "[install-deps] SDKMAN is already installed, skipping download" >&2
    else
        curl -s "https://get.sdkman.io" | bash
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
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.2/install.sh | bash
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
        nvm install --lts
    fi

    # corepack ships no lifecycle scripts, so `--ignore-scripts` costs nothing and
    # keeps a compromised registry response from running code at install time.
    npm install -g --ignore-scripts corepack
    corepack enable
}
# =========================================================================================================
