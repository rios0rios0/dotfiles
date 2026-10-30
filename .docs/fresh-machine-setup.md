# Fresh Machine Setup

A linear runbook for turning an empty machine into a fully configured workstation with this
repository. Follow it top to bottom; nothing later depends on something you skipped. It covers the
three targets in the [platform matrix](../README.md#platform-matrix): Windows 11, Kali Linux on WSL,
and Termux on Android. Baremetal Linux is a variant of the WSL phase and is called out where it
differs.

Every item carries one of three markers:

| Marker        | Meaning                                                                                                                  |
|---------------|--------------------------------------------------------------------------------------------------------------------------|
| `[automated]` | Done by `chezmoi apply`. The script or template that does it is named, so you know where to look when it fails.          |
| `[partial]`   | Started by a script, finished by you: a reboot, a prompt, a login, or a step the script cannot reach.                    |
| `[manual]`    | Not automated. The [automation gaps](#automation-gaps) section at the end lists the ones worth turning into issues.      |

The dependency installers are the long pole: `run_once_before_*-install-dependencies.*` takes
45-120 minutes on WSL and Termux and 30-60 minutes on Windows. Do not cancel them. The `install_*`
guards make a second pass cheap, but a cancelled pass leaves chezmoi thinking the script never ran.

## Phase 0: Things that live outside any machine

These exist once, in 1Password, and every platform reads them at render time. Create them before
touching a machine, or the first `chezmoi init --apply` aborts halfway through rendering.

| Item                                                                                                                  | Vault      | Used by                                                                                                                                                                  |
|-----------------------------------------------------------------------------------------------------------------------|------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `chezmoi.age` Secure Note with `private key` (the whole age identity file) and `public key` fields                                    | `Private`  | `run_before_linux-005-export-private-key.sh.tmpl` and `run_before_windows-004-export-private-key.ps1.tmpl` write the private key to `~/.ssh/chezmoi` before every apply that lacks it, so the `encrypted_*.age` files decrypt; its public key is also in `.chezmoidata/age-keys.yaml`, which `dot_age_recipients.tmpl` renders into `~/.age_recipients` (Windows and Linux; skipped on Android) |
| `omniroute-backup.age` Secure Note with the same fields                                                                               | `Private`  | `run_before_linux-005-export-private-key.sh.tmpl` writes it to `~/.ssh/omniroute-backup-key` on WSL, where `omniroute-backup` encrypts the OmniRoute backups with it; a missing one only warns                                                                                                                 |
| `Device: <deviceName>` Secure Note                                                                                    | `personal` | `dot_gitconfig.tmpl`, `dot_ssh/*`, `dot_docker/config.json.tmpl`, the SSH/GPG/PEM key scripts, and the runtime credential loader                                                 |
| The SSH Key, GPG, PEM and Docker registry items the device note lists in `notesPlain` (`type:Item Name`, one per line) | `Private`  | The same templates                                                                                                                                                       |
| `cred:NAME` and `ws:NAME` fields on the device note                                                                   | `personal` | `dot_scripts/linux-engineering-shell-credentials.sh` and `linux-engineering-workspace-aliases.sh` at shell startup                                                        |
| `Token: ggshield` Secure Note with `token`, `token name` and `workspace id` fields                                  | `Private`  | `dot_config/ggshield/private_auth_config.yaml.tmpl` renders `~/.config/ggshield/auth_config.yaml` (Linux only; one item per user, not per device)                          |
| `Wakatime` item with `api key` and `hidden projects` fields                                                           | `personal` | `dot_wakatime.cfg.tmpl` (Windows only)                                                                                                                                   |

`deviceName` starts from `CHEZMOI_DEVICE` when that variable is set and from the hostname
otherwise, and `.chezmoi.yaml.tmpl` then lowercases the value and replaces spaces with dashes in
both cases. Name the note after that normalized form: a hostname or `CHEZMOI_DEVICE` of `My Laptop`
means `Device: my-laptop`. On Windows and WSL the hostname is fine. On Termux the hostname is
`localhost`, so `CHEZMOI_DEVICE` has to be exported before the first apply (Phase 5).

The MCP servers in `~/.claude.json` are not a render-time dependency: `modify_dot_claude.json`
writes a `${CONTEXT7_API_KEY}` placeholder that Claude Code expands from the environment, so that
name needs a `cred:` field on the device note. Nothing about it blocks the first apply.
[mcp-1password-setup.md](mcp-1password-setup.md) describes the field.

The age identity is only needed where an encrypted file is applied: `.aws` and `.azure` on
Windows; `.npmrc` on Linux. Nothing encrypted is applied
on Android, so Termux never needs `~/.ssh/chezmoi`.

## Phase 1: Firmware and hardware drivers (Windows)

Nothing here is automated, and most of it cannot be: the installers are vendor downloads without a
winget manifest, or with a manifest that is broken (the `#TODO` comments in
`run_once_before_windows-001-install-dependencies.ps1` say which and why).

| Item                                                            | Marker            | Notes                                                                                                                        |
|-----------------------------------------------------------------|-------------------|------------------------------------------------------------------------------------------------------------------------------|
| Wireless driver for the ASUS ROG USB adapter                    | `[manual]`        | Vendor download. Needed before anything else can reach the network.                                                          |
| ASUS Armoury Crate and the board drivers it pulls               | `[manual]`        | `Asus.ArmouryCrate` is commented out: winget never sees it as installed and keeps reinstalling it. Install from asus.com.    |
| AIDA64 Extreme, CPU-Z ROG                                       | `[automated]`     | `FinalWire.AIDA64.Extreme` and `CPUID.CPU-Z.ROG` in the `$hardware` array. Phase 3 installs them; do not install them by hand. |
| AIDA64 OSD label order                                          | `[manual]`        | Configured in the AIDA64 UI after Phase 3.                                                                                   |
| ASUS GPU Tweak III                                              | `[manual]`        | `Asus.GPUTweak` sits in the commented-out `$hardwareDesktop` array (RTX 4090 desktop only).                                  |
| NVIDIA App                                                      | `[manual]`        | nvidia.com download.                                                                                                         |
| Logitech G HUB, PassMark PerformanceTest                        | `[automated]`     | `Logitech.GHUB` and `PassMark.PerformanceTest` in `$hardware`. Phase 3 installs them.                                        |
| Brother full driver                                             | `[manual]`        | Not in the winget source, so `Brother.FullDriver` is commented out; download the model's package from support.brother.com.   |
| Lian Li L-Connect 3, Samsung Magician                           | `[manual]`        | Vendor downloads.                                                                                                            |
| CyberPower PowerPanel Personal, APC PowerChute                  | `[manual]`        | `CyberPowerSystems.PowerPanel.Personal` is in the commented-out `$utilitiesDesktop` array; PowerChute is a vendor download.  |

**Verify:** Device Manager shows no unknown devices, and `Test-NetConnection github.com -Port 443`
succeeds.

## Phase 2: Windows features and WSL

| Item                                                     | Marker        | Notes                                                                                                                                                                                                                                      |
|----------------------------------------------------------|---------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Virtual Machine Platform, Windows Subsystem for Linux    | `[partial]`   | `run_once_before_windows-002-configure-dependencies.ps1` runs `wsl.exe --install -d kali-linux` when no Kali distro exists, which enables both features and installs the distro. The reboot Windows asks for afterwards is on you.         |
| `wsl --update`                                           | `[automated]` | Same script, on machines where Kali already exists. `Microsoft.WSL` in `$requirements` keeps the Store build of WSL current.                                                                                                             |
| `wsl --set-default-version 2`                            | `[manual]`    | Not run anywhere. Windows 11 defaults new distros to WSL 2, so it only matters on an image that was ever switched to 1.                                                                                                                    |
| Kali as the default distro                               | `[automated]` | `wsl.exe --setdefault kali-linux`, same script.                                                                                                                                                                                            |
| First Kali login (UNIX user and password)                | `[manual]`    | WSL prompts for it the first time the distro starts.                                                                                                                                                                                       |

Because `windows-002` runs during the Windows bootstrap, you do not run these commands yourself on a
fresh machine; Phase 3 triggers them. Run them by hand only when adding WSL to a machine that already
went through Phase 3.

**Verify:** after the reboot, `wsl --status` reports `kali-linux` as the default distribution with
version 2, and `wsl -l -v` lists it as `Stopped` or `Running`, not `Installing`.

## Phase 3: Windows bootstrap

Run everything in this phase from an **elevated** PowerShell, which the font step no longer needs
but the machine-wide installers still prompt for. `run_before_windows-003-install-fonts.ps1` installs
the fonts for the current user, without administrator rights, and runs before every apply, so a font
that is missing -- including after the old `run_once_` version exited 0 without elevation and was
never run again -- is installed by the next `chezmoi apply`.

### 3.1 Prerequisites `[manual]`

Every prerequisite comes from winget, so set it up first, from Windows PowerShell:

1. Download `Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle` from the
   [latest winget-cli release](https://github.com/microsoft/winget-cli/releases/latest) and install
   it with `Add-AppxPackage .\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle`. If it reports
   a missing dependency, run `Add-AppxPackage` on each `x64` package in
   `DesktopAppInstaller_Dependencies.zip`, from the same release, and then on the bundle again.
2. Add `C:\Users\<USER>\AppData\Local\Microsoft\WindowsApps` to the user `Path`, where `<USER>` is
   the Windows user name: Start > "Edit environment variables for your account" > `Path` > Edit >
   New. The `winget.exe` alias lives in that folder.
3. Close the terminal and open a new one, which reads the new `Path`, and check that
   `winget --version` answers.

Then:

```powershell
winget install Microsoft.PowerShell          # then reopen the terminal in PowerShell 7
winget install Git.Git                       # if ASLR is enforced, use the installer from git-scm.com instead
winget install FiloSottile.age               # add the age executable to PATH by hand
winget install AgileBits.1Password           # the desktop app; the CLI authenticates through it
winget install AgileBits.1Password.CLI
winget install twpayne.chezmoi
```

Sign in to the 1Password desktop app and enable **Settings > Developer > Integrate with 1Password CLI**.
Both the Windows templates and, in Phase 4, the WSL `op` wrapper (which calls `op.exe` through
interop) authenticate through that integration. `op whoami` must succeed before continuing. If
`op account list` does not show the personal account under the shorthand `my`, add it with
`op account add --address my.1password.com --shorthand my`: the WSL key export signs in with
`--account my`.

### 3.2 Apply `[automated]`

```powershell
Set-ExecutionPolicy RemoteSigned -Scope Process
chezmoi init --apply rios0rios0
```

What runs, in order (all paths under `.chezmoiscripts/`):

| Step | Script                                                                                       | Marker        | What it does                                                                                                                                                                        |
|------|----------------------------------------------------------------------------------------------|---------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 1    | `run_once_before_windows-001-install-dependencies.ps1`                                       | `[automated]` | 36 packages (Spotify from the Microsoft Store, the rest from winget), skipping any that `winget list` finds under its exact ID, plus RustDesk from its GitHub release (section 3.3). |
| 2    | `run_once_before_windows-002-configure-dependencies.ps1`                                     | `[partial]`   | Phase 2: installs Kali and makes it the default distro, or runs `wsl --update` where Kali already exists. The reboot after the install is on you.                                   |
| 3    | `run_before_windows-003-install-fonts.ps1`                                                   | `[automated]` | MesloLGS NF, Meslo Nerd Font and FiraCode Nerd Font for the current user, into `%LOCALAPPDATA%\Microsoft\Windows\Fonts` with `HKCU` font entries, whenever a family is missing; no elevation needed. |
| 4    | `run_before_windows-004-export-private-key.ps1.tmpl`                                         | `[automated]` | Writes the age identity from `op://Private/chezmoi.age/private key` to `~\.ssh\chezmoi`, on every apply where that file is missing or holds another key; a failed read stops the apply. |
| 5    | Managed files                                                                                | `[automated]` | `.gitconfig`, `.ssh\config`, `.ssh\allowed_signers`, `.ssh\authorized_keys`, `.age_recipients`, `.oh-my-posh.json`, `.config\powershell\profile.ps1`, `.wslconfig` (merged), `.wakatime.cfg`, `.aws` and `.azure` (decrypted). |
| 6    | `run_once_after_windows-001-create-ssh-known-hosts.ps1`                                      | `[automated]` | Pre-populates `known_hosts` so git over SSH never hangs on a host-key prompt.                                                                                                       |
| 7    | `run_after_windows-001-create-ssh-public-keys.ps1.tmpl`, `run_after_windows-002-create-ssh-pems.ps1.tmpl` | `[automated]` | SSH public keys and PEM certificates from the items the device note references.                                                                                          |
| 8    | `run_after_windows-003-copy-app-data-files.ps1.tmpl`                                         | `[automated]` | Windows Terminal `settings.json`, whose PowerShell profile starts PowerShell 7 with `~\.config\powershell\profile.ps1` (Oh My Posh), and the Kali icon from `AppData/`. |
| 9    | `run_onchange_after_windows-005-remove-dependencies.ps1`                                     | `[automated]` | Uninstalls tombstoned packages; silent on a fresh machine.                                                                                                                          |
| 10   | `run_onchange_after_windows-006-write-home-agents.ps1.tmpl`                                  | `[automated]` | Writes `~\AGENTS.md`, the agent guide for this machine, in place of the repository's `AGENTS.md` that applies used to deploy there; see "The Home AGENTS.md" in `AGENTS.md`.        |

### 3.3 What the winget pass installs

- `$requirements`: `AgileBits.1Password`, `AgileBits.1Password.CLI`, `FiloSottile.age`, `Git.Git`, `JanDeDobbeleer.OhMyPosh`, `Microsoft.PowerShell`, `Microsoft.WSL`, `Microsoft.WindowsTerminal`, `Tailscale.Tailscale`
- `$hardware`: `CPUID.CPU-Z.ROG`, `FinalWire.AIDA64.Extreme`, `Logitech.GHUB`, `PassMark.PerformanceTest`
- `$utilities`: `BleachBit.BleachBit`, `CharlesMilette.TranslucentTB`, `EaseUS.PartitionMaster`, `GIMP.GIMP`, `Grammarly.Grammarly`, `Microsoft.OneDrive`, `Notepad++.Notepad++`, `PDFLabs.PDFtk.Free`, `Piriform.Recuva`, `RevoUninstaller.RevoUninstallerPro`, `SumatraPDF.SumatraPDF`, `msstore:9NCBCSZSJRSB` (Spotify, Microsoft Store edition)
- `$communication`: `Zoom.Zoom.EXE`
- `$development`: `Docker.DockerDesktop`, `ExpressVPN.ExpressVPN`, `Microsoft.Azure.StorageExplorer`, `Mirantis.Lens`, `OpenVPNTechnologies.OpenVPNConnect`, `BurntSushi.ripgrep.MSVC`
- `$gaming`: `ElectronicArts.EADesktop`, `EpicGames.EpicGamesLauncher`, `GOG.Galaxy`, `Valve.Steam`

An entry counts as installed when `winget list --id <id> --exact --source <source>` finds it;
an entry written `msstore:<id>` comes from the Microsoft Store source. Spotify is one: the
`Spotify.Spotify` installer refuses to run beside the Store edition (exit code 29). A failed install
prints a `WARN` with winget's exit code, and the run ends with a list of everything not installed.

RustDesk is installed right after `$utilities`, but not through winget: its publisher had every
version removed from winget in March 2026, after the package was falsely flagged as malware
([microsoft/winget-pkgs#352094](https://github.com/microsoft/winget-pkgs/issues/352094)).
`Install-RustDesk` downloads the pinned MSI from the [GitHub release](https://github.com/rustdesk/rustdesk/releases)
and installs it only if its SHA-256 matches and its Authenticode signature is valid and from `PURSLANE`,
RustDesk's publisher. It skips machines where RustDesk is already installed, whether from the `.exe`
or the MSI. The MSI installs per machine, so a non-elevated apply shows a UAC prompt for it.

Commented out in the script with the reason, so `[manual]`: `Asus.ArmouryCrate` (never detected as
installed), `Brother.FullDriver` (not in the winget source), `Blizzard.BattleNet` (asks for a path
and never installs), `Ubisoft.Connect` (hash mismatch, Windows blocks the installer), and the
desktop-only `Asus.GPUTweak` and `CyberPowerSystems.PowerPanel.Personal`.

**Verify:**

```powershell
chezmoi doctor
winget list --id Docker.DockerDesktop
oh-my-posh version
Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Fonts" -Filter 'MesloLGS*'
Test-Path ~\.ssh\chezmoi
docker run --rm hello-world          # after starting Docker Desktop once and accepting its terms
Get-Service RustDesk                 # Running once Install-RustDesk has installed it
```

## Phase 4: Kali on WSL bootstrap

Open the Kali distro (Windows Terminal has a profile for it since Phase 3) and run:

```sh
sudo apt install git age
sh -c "$(curl -fsLS get.chezmoi.io/lb)" -- init --apply rios0rios0
```

WSL has no `op` binary of its own. `run_once_before_linux-001-create-op-wrapper.sh` writes
`~/.local/bin/op`, which calls `op.exe` through interop, so the 1Password desktop integration from
Phase 3 is what authenticates every template here.

| Step | Script                                                        | Marker        | What it does                                                                                                                                                                                                 |
|------|---------------------------------------------------------------|---------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 1    | `run_once_before_linux-001-create-op-wrapper.sh`              | `[automated]` | The `op` wrapper above.                                                                                                                                                                                      |
| 2    | `run_once_before_linux-002-install-dependencies(baremetal).sh` | `[automated]` | Sorts before the main installer, so it runs first; exits immediately on WSL. On baremetal Debian or Ubuntu it adds `barrier`, `bleachbit`, `gimp`, `octave`, `scrcpy`, `unetbootin`, `vlc` and `pdftk`, then Genymotion, Reactotron, R-Linux, Slack and VirtualBox. |
| 3    | `run_once_before_linux-002-install-dependencies.sh`           | `[automated]` | apt packages plus every tool in the table below. 45-120 minutes.                                                                                                                                             |
| 4    | `run_once_before_linux-003-configure-dependencies.sh`         | `[automated]` | Symlinks Debian's `batcat` to `~/.local/bin/bat`.                                                                                                                                                            |
| 5    | `run_once_before_linux-004-install-fonts.sh.tmpl`             | `[automated]` | The same three font families into `~/.fonts`, then `fc-cache`.                                                                                                                                              |
| 6    | `run_before_linux-005-export-private-key.sh.tmpl`             | `[automated]` | On every apply where a key is missing or differs: signs in with `op signin --account my` and writes the chezmoi age key to `~/.ssh/chezmoi`, on WSL the OmniRoute backup key, and the aisync key to `~/.config/aisync/key.txt` (only when it is missing). |
| 7    | Managed files                                                 | `[automated]` | `.zshrc`, `.zshenv`, `.p10k.zsh`, `.tmux.conf`, `.gitconfig`, `.age_recipients`, `.docker/config.json`, `.config/ggshield`, the `ssh` and `ssh-add` wrappers in `~/.local/bin`, `.scripts/*`, `~/.claude.json` (MCP servers), Atuin's `.config/atuin/config.toml`, and the decrypted `.npmrc`. `.ssh/config` is Windows and Android only. |
| 8    | `run_once_after_linux-002-clone-pentesting-tools.sh`          | `[automated]` | Clones VHostScan, dirsearch, StegCracker and stegbrute into `~/Development/Tools`.                                                                                                                           |
| 9    | `run_after_linux-002-import-gpg-keys.sh.tmpl`                 | `[automated]` | Imports the GPG keys the device note references.                                                                                                                                                             |
| 10   | `run_after_linux-004-install-ggshield-hook.sh`                | `[automated]` | Generates the global GitGuardian pre-commit hook; `core.hooksPath` in `.gitconfig` points at it.                                                                                                             |
| 11   | `run_after_linux-005-install-jetbrains-themes.sh`             | `[partial]`   | Fans the themes staged in `~/.local/share/jetbrains-themes` out to every JetBrains IDE under `~/.config/JetBrains`. Nothing to do until an IDE has a config directory there; re-run `chezmoi apply` after installing one. |
| 12   | `run_onchange_after_linux-006-remove-dependencies.sh.tmpl`    | `[automated]` | Tombstones; silent on a fresh machine.                                                                                                                                                                       |
| 13   | `run_onchange_after_linux-007-setup-sentry-cli.sh.tmpl`      | `[automated]` | Raises a CLI older than `0.47.0` (the floor `sentry-ds` needs) with `sentry cli upgrade`, failing until it holds; then `sentry cli setup --no-modify-path`: the zsh completion into `~/.local/share/zsh/site-functions`, and the Claude Code skill once `~/.claude` exists (the next `sentry cli upgrade` adds it otherwise). |
| 14   | `run_onchange_after_linux-011-setup-chrome.sh`               | `[automated]` | Google Chrome from Google's apt repository, for the Chrome DevTools MCP server; asks for the sudo password. Its key is trusted for that repository only, and only once its fingerprint proves it Google's. |
| 15   | `run_onchange_after_linux-012-setup-claude-lsp.sh`           | `[automated]` | Pinned `gopls` (into `~/.local/bin`), `typescript-language-server` and `pyright`, and the `gopls-lsp`, `typescript-lsp` and `pyright-lsp` plugins at user scope. Claude Code loads them at its next start. Adding the plugins' marketplace prints `SSH not configured, cloning via HTTPS`, which is expected. Claude Code first tries `ssh -T git@github.com` for 3 seconds without prompting, and the first apply cannot pass that: it runs from bash, before `~/.local/bin` and its `ssh.exe` wrapper are on `PATH`, and Linux's own `ssh` knows no GitHub host key. The repository is public, so HTTPS clones it without credentials. |
| 16   | `run_after_linux-014-sync-aifiles.sh.tmpl`                   | `[automated]` | Clones aifiles into `~/.config/aisync/repo` if needed and pulls it into `~/.claude` and `~/.config/opencode`: instructions, settings, rules, agents, commands, hooks, skills, Claude's project memories and recent conversations. The first sync lets aifiles' copy win, after backing up every local file it may replace to `/tmp/aifiles-first-sync.*`; after that an apply pulls only when aifiles moved. It never prompts, pushes or fails the apply. |
| 17   | `run_after_linux-015-start-omniroute.sh.tmpl`                 | `[partial]`   | WSL only. Starts the OmniRoute stack when its data volume exists, and never creates the database: on a fresh machine it names the archive to restore instead. `omniroute-restore` brings this machine's newest archive back, and `omniroute-restore --device <name>` one another machine copied to the personal OneDrive, with `.env` from the archive or 1Password; see [Restore](omniroute-local.md#restore). Also says when Docker Desktop does not start at sign-in. |
| 18   | `run_onchange_after_linux-019-write-home-agents.sh.tmpl`      | `[automated]` | Writes the agent guide for this machine (the `cp`/`rm`/`mv` guards, eza, quoting through each layer, the git rules) to `~/AGENTS.md` for OpenCode and `~/CLAUDE.md` for Claude Code, in place of the repository's `AGENTS.md` that applies used to deploy there and of aisync's two global instruction files, which `.chezmoiremove` deletes; see "The Home AGENTS.md" in `AGENTS.md`.                                                                                                                                                                                                                                |

### What the dependency installer provides

apt, from the `requirements`, `hardware` and `utilities` arrays: `git`, `curl`, `zip`, `unzip`, `xz-utils`,
`zstd`, `age`, `gpg`, `gpg-agent`, `zsh`, `eza`, `sqlite3`, `bsdmainutils`, `binutils`, `bison`, `gcc`,
`clang`, `make`, `htop`, `screenfetch`, `jq`, `bat`, `ripgrep`, `silversearcher-ag`,
`inotify-tools`, `dos2unix`, `expect`, `aria2`, `file`, `parallel`, `cloc`, `rename`, `whois`,
`ffmpeg`, `sox`, `libsox-fmt-pulse`, `rsync`, `asciinema`, `shellcheck`, `postgresql-client`.

| Tool                                             | Function                             | Marker        | Notes                                                                                                                           |
|--------------------------------------------------|--------------------------------------|---------------|---------------------------------------------------------------------------------------------------------------------------------|
| Oh My Zsh, login shell switched to zsh           | `install_oh_my_zsh`, then `usermod`  | `[automated]` | Powerlevel10k and the plugins load through ZINIT from `.zshrc`; there is nothing to install for them.                            |
| Go, via GVM                                      | `install_gvm`                        | `[automated]` | Resolves the latest stable release from go.dev on every run.                                                                    |
| kubectl (`v1.32` apt channel), krew with `ctx` and `ns` | `install_kubectl`, `install_krew` | `[automated]` |                                                                                                                                 |
| terra (Terraform and Terragrunt manager)         | `install_terra`                      | `[automated]` | Upstream install script, then `terra self-update` and `terra update` with `TERRA_ASSUME_YES=true`, so an unattended run updates instead of reporting "Non-interactive session - skipping update". |
| Java and Gradle, via SDKMAN                      | `install_sdkman`                     | `[automated]` | Latest candidates, refreshed on every run.                                                                                      |
| Node.js LTS, via NVM `v0.40.2`, plus corepack    | `install_nvm`                        | `[automated]` | npm is upgraded to its latest release with `nvm install-latest-npm` on every pass.                                              |
| Python `3.13.2`, via pyenv                       | `install_pyenv`                      | `[automated]` | Also installs the apt build dependencies pyenv needs, and upgrades that Python's pip to the latest release.                     |
| Flutter (current stable, with its Dart)          | `install_flutter`                    | `[automated]` | The official Linux x64 tarball, resolved from Flutter's releases manifest and verified against the SHA-256 it publishes, under `~/.local/share/flutter`; `flutter` and `dart` are linked into `~/.local/bin`, so a Dart SDK that was there by hand is repointed (logged). An installed SDK moves to the next stable with `flutter upgrade`. Web artifacts are precached; the Android toolchain, Chrome and the Linux desktop toolchain that `flutter doctor` lists are deliberately not installed. |
| bun (the `ocode` fork build's runtime)           | `install_bun`                        | `[automated]` | Upstream `bun.sh/install` into `~/.bun`, run with `SHELL` empty so its shell detection cannot append a PATH line to an rc file chezmoi owns; `dot_zshenv.tmpl` adds `~/.bun/bin` to PATH. The `ocode` build itself installs and builds with the bun the fork checkout pins, so when this one is another version the first apply also downloads the pinned one into `~/.cache/ocode-bun/<version>/`. |
| Claude Code                                      | `install_claude_cli`                 | `[automated]` | Anthropic's native build from `claude.ai/install.sh`, checked against the SHA-256 in Anthropic's release manifest, behind `~/.local/bin/claude`; it updates itself. A failed install fails the apply, which retries it. |
| ccswitch                                         | `install_ccswitch`                   | `[partial]`   | Installed here; every account still has to be enrolled once with `ccswitch enroll` after `claude` and `/login`.                 |
| Sentry CLI                                       | `install_sentry_cli`                 | `[automated]` | npm package (`sentry`, from getsentry/cli), shared with Android through `lib-install-deps.sh`; completions and the agent skill come from step 13.                                  |
| Neon CLI                                         | `install_neon_cli`                   | `[automated]` | npm package (`neon`, from neondatabase/neon-pkgs), shared with Android through `lib-install-deps.sh`; fresh installs take the `neon` package, not the legacy `neonctl` compatibility shim. |
| dev-toolkit                                      | `install_dev_toolkit`                | `[automated]` | Upstream install script.                                                                                                        |
| GitHub CLI                                       | `install_github_cli`                 | `[automated]` | apt repository.                                                                                                                 |
| AWS CLI v2                                       | `install_aws_cli`                    | `[automated]` | Official zip installer.                                                                                                         |
| Azure CLI                                        | `install_azure_cli`                  | `[automated]` | pip, inside the pyenv Python.                                                                                                   |
| Fly.io CLI                                        | `install_fly_cli`                     | `[automated]`  | Upstream installer into `~/.fly/bin`; `dot_zshenv.tmpl` adds it to PATH.                                                         |
| OCI CLI                                           | `install_oci_cli`                     | `[automated]`  | pip, inside the pyenv Python.                                                                                                    |
| ggshield                                         | `install_ggshield`                   | `[automated]` | pipx; its auth config is rendered from 1Password by `dot_config/ggshield/private_auth_config.yaml.tmpl`.                         |
| ruff                                             | `install_ruff`                       | `[automated]` | Astral install script.                                                                                                          |
| yq                                               | `install_yq`                         | `[automated]` | mikefarah's release, pinned and SHA-256 checked, into `~/.local/bin`; Kali's apt `yq` is a different tool.                      |
| Atuin (shell history)                            | `install_atuin`                      | `[partial]`   | The release tarball, pinned and SHA-256 checked, into `~/.local/bin`; `.zshrc` starts it. The account login and the one-time import of the zsh-histdb history are by hand (below). |
| aisync                                           | `install_aisync`                     | `[automated]` | Installed here; `run_after_linux-014` clones aifiles and pulls it after every apply.                                            |
| Atlassian CLI                                    | `install_acli`                       | `[automated]` |                                                                                                                                 |
| Speedtest CLI                                    | `install_speedtest_cli`              | `[automated]` | Ookla apt repository.                                                                                                           |

Nothing installs these, so they are `[manual]`: `imagemagick` (commented out in the `utilities`
array, with an open question about doing it on Windows instead), `pdftk` on WSL (only the baremetal
script and Windows have it), PDM, and the CycloneDX CLI (`.zshrc` aliases `cydx` to a binary you
place in `~/Development/Tools/Cyclonedx` yourself).

### After the apply `[manual]`

```sh
exec zsh                                   # first zsh: ZINIT clones Powerlevel10k and the plugins
claude                                     # /login, then: ccswitch enroll
sentry auth login                          # device code entered at a URL; `--token <API token>` skips OAuth
neon login                                 # browser flow; `NEON_API_KEY` or `neon profile create <name> --api-key -` (stdin) skips it
atuin login -u <username>                  # the password and key from the `Atuin` item in 1Password
```

Then import the zsh-histdb history once and run `atuin sync`. On `alien-a51`, which runs the Atuin
server, that means starting the server and registering the account first, and importing only the
laptop's own commands. [atuin-sync.md](atuin-sync.md) has the commands for each device.

aisync needs nothing here: the apply fetched its key, cloned aifiles into `~/.config/aisync/repo`
and pulled it, letting aifiles' copy win over what was there, which it backed up to an
`aifiles-first-sync.*` directory in `/tmp` first (see "AI Rules Sync" in CLAUDE.md). Never run a bare
`aisync init`, which generates a new key, nor `aisync source add`, which breaks every later pull. When
an apply reports changes on both sides, settle them with `aisync sync` in a terminal.

If `docker` should work inside Kali through Docker Desktop, enable its WSL integration for
`kali-linux` under Docker Desktop's settings.

**Verify:**

```sh
chezmoi doctor
echo "$SHELL"                              # /usr/bin/zsh
op whoami
gvm list && go version
node --version && corepack --version
pyenv version
kubectl version --client && kubectl krew list
command -v terra terraform terragrunt aws az gh sentry neon acli ruff ggshield aisync ccswitch flyctl oci bun atuin
atuin status                               # logged in, and the last sync
ls ~/.local/share/zsh/site-functions/_sentry
fc-list | grep -i meslo
git config --get core.hooksPath
```

**Baremetal Linux** is `[partial]`: `run_once_before_linux-001-create-op-wrapper.sh` always writes a
wrapper that calls `op.exe`, and `run_before_linux-005-export-private-key.sh.tmpl` defines `op` the
same way, so a machine without Windows interop needs the native 1Password CLI installed and both
scripts worked around by hand. The baremetal installer itself only runs outside WSL.

## Phase 5: Termux on Android

Install Termux from [F-Droid](https://f-droid.org/en/packages/com.termux/), not the Play Store.
Then, in Termux:

```sh
apt install git chezmoi
export CHEZMOI_DEVICE="$(getprop ro.product.model)"
chezmoi init --apply rios0rios0
```

`CHEZMOI_DEVICE` matters only for this first run: `.zshrc` exports it in every later shell, but
`.zshrc` does not exist yet, and without it the hostname `localhost` would make every template look
for a note called `Device: localhost`.

The Android bootstrap is interactive at four points, all `[partial]`, so stay near the phone:
`termux-setup-storage` (an Android permission dialog), `termux-change-repo` (the mirror picker), the
first call to the `op` wrapper (it runs `op account add --address my.1password.com --shorthand my`
and asks for the account credentials), and the Oh My Zsh installer, which may ask to change the shell
and then drop you into zsh: type `exit` to let the installer continue.

| Step | Script                                                              | Marker        | What it does                                                                                                                                    |
|------|---------------------------------------------------------------------|---------------|-------------------------------------------------------------------------------------------------------------------------------------------------|
| 1    | `run_once_before_android-001-create-wrapper.sh`                     | `[automated]` | The generic `termux-etc-seccomp` wrapper every tool wrapper uses.                                                                               |
| 2    | `run_once_before_android-001a` to `001e`                            | `[automated]` | The `op`, `gh`, `golangci-lint`, `acli` and `claude` wrappers, plus `claude-zsh`, the shell Claude Code's tool calls start through (from `001e`). They must exist before the installer and the templates call the tools.           |
| 3    | `run_once_before_android-002-install-dependencies.sh.tmpl`          | `[partial]`   | Termux packages and the tools below. 45-120 minutes, with the prompts listed above.                                                             |
| 4    | `run_once_before_android-003-install-fonts.sh.tmpl`                 | `[automated]` | The fonts into `~/.local/share/fonts` and `~/.termux/font*.ttf`.                                                                                |
| 5    | Managed files                                                       | `[automated]` | `.zshrc`, `.zshenv`, `.p10k.zsh`, `.tmux.conf`, `.gitconfig`, `.ssh/*`, `.termux/termux.properties`, `.config/mcphub/servers.json`, the `.config/nvim` plugin specs, `.claude/*`, `.local/bin/wrapper`, `.scripts/*`. |
| 6    | `run_after_android-001-create-ssh-keys.sh.tmpl`                     | `[automated]` | Writes the SSH keys the device note references.                                                                                                 |
| 7    | `run_after_android-003-wrap-terra-clis.sh`                          | `[automated]` | Re-wraps `terraform`, `terragrunt` and `flyctl` (with its `fly` alias) on every apply, because `terra update` and `flyctl version upgrade` overwrite them.                                                   |
| 8    | `run_onchange_after_android-004-remove-dependencies.sh.tmpl`        | `[automated]` | Tombstones.                                                                                                                                     |
| 9    | `run_after_android-005-prune-tmp-modcache.sh`                       | `[automated]` | Deletes Go module caches left under `$TMPDIR`, which otherwise crash Termux on exit.                                                            |
| 10   | `run_after_android-007-build-claude-exec-shim.sh`                   | `[automated]` | Compiles `~/.local/bin/claude-exec-shim` with `clang`, so Claude Code's `grep` and `find` can run its musl binary without `LD_PRELOAD`.          |
| 11   | `run_onchange_after_android-006-setup-sentry-cli.sh.tmpl`           | `[automated]` | Raises a CLI older than `0.47.0` (the floor `sentry-ds` needs) with `sentry cli upgrade`, failing until it holds; then `sentry cli setup --no-modify-path`: the zsh completion and the Claude Code skill (`~/.claude` is managed here, so it already exists). |
| 12   | `run_after_android-008-sync-aifiles.sh.tmpl`                        | `[automated]` | The same pull as Linux's step 16. The key is rendered from 1Password on an apply that finds none, and `~/.config/aisync/exclude` keeps aifiles' Linux/WSL copies of `settings.json`, `CLAUDE.md` and `AGENTS.md` off the phone. It needs aisync 1.7.0; an older one is reported with the command that rebuilds it. |
| 13   | `run_onchange_after_android-011-write-home-agents.sh.tmpl`          | `[automated]` | The same guide as Linux's step 18, in both files, rendered for Termux.                                                                                                                                                                  |

### What the dependency installer provides

Termux packages: `git`, `curl`, `zip`, `unzip`, `age`, `eza`, `sqlite`, `vim`, `neovim`, `bison`,
`make`, `wget`, `zsh`, `ncurses-utils`, `proot`, `proot-distro`, `clang`, `cmake`, `file`,
`patchelf`, `htop`, `screenfetch`, `jq`, `yq`, `bat`, `ripgrep`, `silversearcher-ag`,
`inotify-tools`, `dos2unix`, `expect`, `which`, `mlocate`, `openssh`, `netcat-openbsd`, `parallel`,
`rsync`, `rclone`, `dnsutils`, `tmux`, `atuin`, `shellcheck`, `postgresql`, `ruff`, `golang`, `rust`,
`nodejs`, `python`, `python-pip`, `dart`.

| Tool                                                              | Function                                                                          | Marker        | Notes                                                                                                                                                                                              |
|-------------------------------------------------------------------|-----------------------------------------------------------------------------------|---------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Oh My Zsh                                                         | `install_oh_my_zsh`                                                               | `[partial]`   | See the prompt above. The login shell ends up as zsh (`~/.termux/shell`).                                                                                                                          |
| termux-etc-redirect (`termux-etc-seccomp`, `termux-etc-mount`)    | `install_termux_etc_redirect`                                                     | `[automated]` | Built from source; also writes `$PREFIX/etc/resolv.conf`.                                                                                                                                          |
| terra, dev-toolkit, aisync                                        | `install_go_tool_from_source`                                                     | `[automated]` | Built with Termux's native Go. GVM is skipped on purpose: standard Go builds trip Android's seccomp filter.                                                                                         |
| kubectl (ARM64 binary)                                            | `install_kubectl`                                                                 | `[automated]` |                                                                                                                                                                                                    |
| Java and Gradle, via SDKMAN                                       | `install_sdkman`                                                                  | `[automated]` |                                                                                                                                                                                                    |
| Node.js                                                           | `install_nvm`                                                                     | `[automated]` | Keeps the native `nodejs` package and enables corepack; NVM is not used.                                                                                                                           |
| Python                                                            | `install_pyenv`                                                                   | `[automated]` | Keeps the native `python`; pyenv is not used.                                                                                                                                                      |
| Flutter `3.47.5` (community build)                                | `install_flutter`                                                                 | `[partial]`   | Flutter publishes no Linux arm64 host SDK, so this is [GeneralKaos666/flutter-for-termux](https://github.com/GeneralKaos666/flutter-for-termux) — mumumusuc's bionic cross-build as a Termux `.deb` — pinned to a version and an **integrity-only** SHA-256 computed from the inspected file (the project's README hash did not match its asset; the package's framework revision, engine revision and Dart version equal Google's 3.47.5 tarball, which is the corroboration on record), `apt`-installed under `$PREFIX/opt/flutter` with `x11-repo` for its gtk3 dependency, and fronted by two bash wrappers in `~/.local/bin`. **Not yet run on a device**: `flutter --version` is the hard check, `precache --web` is reported and not fatal. Termux's own `dart` package (above) is the baseline for `dart format` either way. |
| Claude Code                                                       | none                                                                              | `[manual]`    | The musl build is bootstrapped by hand following `examples/claude-code.md` in [rios0rios0/termux-etc-redirect](https://github.com/rios0rios0/termux-etc-redirect); the `claude` wrapper from step 2 handles every later update. |
| Sentry CLI                                                        | `install_sentry_cli`                                                              | `[automated]` | npm package under Termux's native Node, no wrapper: the bundle is plain JavaScript. The official install script cannot be used here, its Bun-compiled glibc binary does not start on bionic. Completions and the agent skill come from step 10. |
| Neon CLI                                                          | `install_neon_cli`                                                                | `[automated]` | npm package under Termux's native Node, no wrapper: the bundle is plain JavaScript; its `--keyring` addon has no android build, so credentials stay in the CLI's config file. On the phone, use an API key: `neon profile create <name> --api-key -` reads it from stdin. |
| 1Password CLI (ARM64 binary), GitHub CLI, golangci-lint, Atlassian CLI | `install_1password_cli`, `install_github_cli`, `install_golangci_lint`, `install_acli` | `[automated]` | Pinned release downloads into `~/.local/bin`, run through the wrappers.                                                                                                                  |
| AWS CLI v2                                                        | `install_aws_cli`                                                                 | `[automated]` | Built from source with pip, 10-15 minutes.                                                                                                                                                         |
| Azure CLI                                                         | `install_azure_cli`                                                               | `[automated]` | pip, with the psutil and PyNaCl workarounds Termux needs.                                                                                                                                          |
| Fly.io CLI                                                         | `install_fly_cli`                                                                  | `[automated]`  | Static linux/arm64 Go binary from the upstream installer into `~/.fly/bin`; wrapped by `run_after_android-003` because it cannot resolve DNS unwrapped.                                                                                                         |
| OCI CLI                                                            | `install_oci_cli`                                                                  | `[automated]`  | pip, with the `crc32c` wheel pre-built with the CRC and AES target features forced (Termux's clang ignores the GCC pragma).                                                                         |
| Neovim with AstroNvim                                             | `configure_neovim`                                                                | `[automated]` |                                                                                                                                                                                                    |

### After the apply `[manual]`

Same `claude`, `sentry auth login` and `atuin login` steps as Phase 4, minus `ccswitch` (Linux
only), with Neon authenticated by an API key rather than the browser flow
(`neon profile create <name> --api-key -` reads it from stdin). Then import the phone's zsh-histdb
history into Atuin under its device name, as [atuin-sync.md](atuin-sync.md) shows for Termux. Then
the Android settings
from the README's known issue on the Phantom Process Killer: **Developer Options > Disable child
process restrictions**, Termux's battery usage set to Unrestricted, and optionally Termux:Boot with a
`termux-wake-lock` start script. rclone for OneDrive has its own guide:
[rclone-onedrive-setup.md](rclone-onedrive-setup.md).

**Verify:**

```sh
chezmoi doctor
echo "$CHEZMOI_DEVICE"
readlink ~/.termux/shell                   # .../usr/bin/zsh
op whoami
gh auth status
command -v terra kubectl aws az acli golangci-lint aisync flyctl oci sentry neon
claude --version
sentry --version
neon --version
ls ~/.local/share/zsh/site-functions/_sentry ~/.claude/skills/sentry-cli/SKILL.md
ls ~/.local/bin/claude-exec-shim       # built by run_after_android-007
ls ~/.local/bin/claude-zsh             # written by run_once_before_android-001e
ls ~/.termux/font.ttf
```

## Phase 6: Manual installs, logins and restores (Windows)

Everything left is a download, a login or a license. The order does not matter within this phase.

| Item                                                                         | Marker     | Notes                                                                                                                                                     |
|------------------------------------------------------------------------------|------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------|
| Microsoft account, OneDrive, Edge, Steam and the other launchers             | `[manual]` | Logins. `Microsoft.OneDrive` and the launchers themselves came from Phase 3.                                                                              |
| Docker Desktop first start                                                   | `[manual]` | Accept the terms, sign in, enable WSL integration for `kali-linux` if wanted.                                                                             |
| Microsoft Store apps: WhatsApp, Telegram, CineBench, draw.io, JW Library     | `[manual]` | 1Password, Spotify, TranslucentTB and Oh My Posh from the same list already came from winget in Phase 3.                                                  |
| Office 365, Notion                                                           | `[manual]` | account.microsoft.com and notion.so downloads.                                                                                                            |
| Licenses: AIDA64 Extreme, Revo Uninstaller Pro, EaseUS Partition Master, PerformanceTest, ExpressVPN, Grammarly | `[manual]` | The apps are installed; the keys and accounts are not.                                                                        |
| Battle.net, Ubisoft Connect, Mavis HUB                                       | `[manual]` | The first two have broken winget manifests (Phase 3); Mavis HUB has none.                                                                                 |
| Watchtower                                                                   | `[manual]` | A container that updates other containers; run it on Docker Desktop yourself.                                                                             |
| Authy Desktop, NiceHash Miner                                                | `[manual]` | Twilio discontinued the Authy desktop app in 2024; NiceHash is still a question mark on the original checklist.                                           |
| AIDA64 OSD labels, Windows Terminal profiles beyond the managed `settings.json` | `[manual]` | UI configuration.                                                                                                                                       |
| Restore backups                                                              | `[manual]` | After copying files in from Windows, strip the alternate data streams: `find . -name "*:Zone.Identifier" -type f -delete` from WSL.                        |

**Verify:** `winget list` shows the Store and vendor apps you installed, and every launcher opens
signed in.

## Automation gaps

Candidates for future issues, in rough order of payoff:

1. **Microsoft Store apps.** winget can install from the Store through its `msstore` source; the IDs for WhatsApp, Telegram, CineBench, draw.io and JW Library need to be looked up with `winget search --source msstore` and added to the Windows installer.
2. **Hardware profiles.** `$hardwareDesktop` and `$utilitiesDesktop` are commented out; a chezmoi data flag keyed on the hostname could enable them on the desktop only.
3. **Broken winget manifests**: `Asus.ArmouryCrate`, `Blizzard.BattleNet`, `Ubisoft.Connect`. Re-test them periodically, or install from the vendor URL with a checksum.
4. **Windows features up front.** A small elevated pre-step could enable Virtual Machine Platform and WSL and run `wsl --set-default-version 2` before winget, instead of relying on `wsl --install` inside `windows-002`.
5. **Baremetal Linux 1Password.** `linux-001` and `linux-005` assume `op.exe`.
6. **Post-install steps that need a token**: `ccswitch enroll`, the Claude Code bootstrap on Android. The `cred:` fields on the device note could feed them.
7. **`imagemagick`, `pdftk` on WSL, PDM**: decide where they belong and add them to the installers or drop them from the checklist.
8. **Zone.Identifier cleanup** after a backup restore could live in a `dot_scripts` helper.
9. **Flutter on Termux is unverified.** `install_flutter` in the Android installer was written from `dpkg-deb` inspection of the community package, not from a run on a device. Run one `chezmoi apply` on the phone and record whether `flutter --version`, `flutter precache --web` and `flutter test` work; if the package cannot be made to start, demote the row to `[manual]` and keep only the native `dart`.

## Appendix: the original checklist, item by item

The checklist from issue [#30](https://github.com/rios0rios0/dotfiles/issues/30), mapped to what the
repository does today. Items the Windows setup has since dropped are left out: the JetBrains Toolbox
with the IDEs and ReSharper installed through it, Visual Studio, Postman, Go and jq. Script paths are
under `.chezmoiscripts/`; winget IDs refer to `run_once_before_windows-001-install-dependencies.ps1`.

### Drivers

| Item                                     | Status                                                    |
|------------------------------------------|-----------------------------------------------------------|
| Wireless driver with ASUS ROG USB        | `[manual]`                                                |
| Armoury Crate, all drivers               | `[manual]`, `Asus.ArmouryCrate` commented out             |
| Tools: AIDA64                            | `[automated]` `FinalWire.AIDA64.Extreme`                  |
| AIDA64 OSD label order                   | `[manual]`                                                |
| Tools: CPUID CPU-Z                       | `[automated]` `CPUID.CPU-Z.ROG`                           |
| GPU Tweak                                | `[manual]`, `Asus.GPUTweak` commented out (desktop only)  |
| NVIDIA App                               | `[manual]`                                                |
| Logitech G HUB                           | `[automated]` `Logitech.GHUB`                             |
| Lian Li L-Connect 3                      | `[manual]`                                                |
| Samsung Magician                         | `[manual]`                                                |

### Essentials

| Item       | Status                                        |
|------------|-----------------------------------------------|
| Watchtower | `[manual]`, a container you run on Docker Desktop |

### Windows

| Item                                       | Status                                                                 |
|--------------------------------------------|------------------------------------------------------------------------|
| Windows Features: Virtual Machine Platform | `[partial]`, enabled by `wsl --install` in `windows-002`, reboot is yours |
| Windows Features: WSL                      | `[partial]`, same                                                      |
| `wsl --update`                             | `[automated]` `windows-002`                                            |
| `wsl --set-default-version 2`              | `[manual]`, not run anywhere                                           |
| `wsl --install kali-linux`                 | `[automated]` `windows-002` (`--install -d kali-linux`, then `--setdefault`) |

### Microsoft Store

| Item          | Status                                                          |
|---------------|-----------------------------------------------------------------|
| 1Password     | `[automated]` `AgileBits.1Password` (winget build, not the Store one) |
| WhatsApp      | `[manual]`                                                      |
| Spotify       | `[automated]` `msstore:9NCBCSZSJRSB` (Store edition)            |
| Telegram      | `[manual]`                                                      |
| TranslucentTB | `[automated]` `CharlesMilette.TranslucentTB`                    |
| CineBench     | `[manual]`                                                      |
| oh-my-posh    | `[automated]` `JanDeDobbeleer.OhMyPosh`                         |
| Draw.io       | `[manual]`                                                      |
| JW Library    | `[manual]`                                                      |

### Office utilities

| Item                                | Status                                                                                       |
|-------------------------------------|----------------------------------------------------------------------------------------------|
| Notion                              | `[manual]`                                                                                   |
| Grammarly                           | `[automated]` `Grammarly.Grammarly`                                                          |
| PassMark PerformanceTest            | `[automated]` `PassMark.PerformanceTest`                                                     |
| EaseUS Partition Master Professional | `[automated]` `EaseUS.PartitionMaster`; the license is `[manual]`                            |
| Revo Uninstaller Pro                | `[automated]` `RevoUninstaller.RevoUninstallerPro`; the license is `[manual]`                |
| Adobe Acrobat Reader                | `[automated]` as SumatraPDF, `SumatraPDF.SumatraPDF`; it fills no forms, so those open in Edge's built-in viewer |
| CCleaner Professional               | `[automated]` as BleachBit, `BleachBit.BleachBit`, which needs no license                    |
| Recuva                              | `[automated]` `Piriform.Recuva`                                                              |
| PowerChute Serial Shutdown          | `[manual]`                                                                                   |
| ExpressVPN                          | `[automated]` `ExpressVPN.ExpressVPN`                                                        |
| Notepad++                           | `[automated]` `Notepad++.Notepad++`                                                          |
| Office 365                          | `[manual]`                                                                                   |
| Zoom Workplace                      | `[automated]` `Zoom.Zoom.EXE`                                                                |
| Authy Desktop                       | `[manual]`, discontinued upstream                                                            |
| GIMP                                | `[automated]` `GIMP.GIMP`                                                                    |
| Brother Full Setup                  | `[manual]` not in the winget source                                                          |
| `sudo apt install pdftk imagemagick` | `[manual]` on WSL: neither is installed there; `pdftk` is on Windows (`PDFLabs.PDFtk.Free`) and baremetal Linux |
| CyberPower Personal                 | `[manual]`, `CyberPowerSystems.PowerPanel.Personal` commented out (desktop only)             |

### Development

| Item                                                        | Status                                                                                                   |
|-------------------------------------------------------------|----------------------------------------------------------------------------------------------------------|
| Docker Desktop                                              | `[automated]` `Docker.DockerDesktop`                                                                     |
| Git                                                         | `[automated]` `Git.Git`, with the ASLR caveat in the README                                              |
| OpenVPN Connect                                             | `[automated]` `OpenVPNTechnologies.OpenVPNConnect`                                                       |
| K8s Lens                                                    | `[automated]` `Mirantis.Lens`                                                                            |
| PowerShell 7                                                | `[partial]`, installed by hand as a prerequisite, kept by `Microsoft.PowerShell`                         |
| `oh-my-posh font install meslo`                             | `[automated]` by `run_before_windows-003-install-fonts.ps1` instead                                                 |
| 1Password CLI                                               | `[automated]` `AgileBits.1Password.CLI`, also a prerequisite                                              |
| chezmoi on Windows                                          | `[manual]` prerequisite, `twpayne.chezmoi`                                                               |
| age on Windows                                              | `[automated]` `FiloSottile.age`                                                                          |
| WSL: Oh My Zsh                                              | `[automated]` `install_oh_my_zsh`                                                                        |
| WSL: pyenv, build dependencies, `pyenv global`              | `[automated]` `install_pyenv` (Python `3.13.2`)                                                          |
| WSL: `pip install pdm`                                      | `[manual]`                                                                                               |
| WSL: Powerlevel10k                                          | `[automated]` by ZINIT in `dot_zshrc.tmpl`                                                               |
| WSL: NVM                                                    | `[automated]` `install_nvm`                                                                              |
| WSL: SDKMAN, Java, Gradle                                   | `[automated]` `install_sdkman` (latest candidates, not the pinned `21.0.3-amzn` and `8.9`)                |
| WSL: kubectl, krew, `ctx`, `ns`                             | `[automated]` `install_kubectl`, `install_krew`                                                          |
| WSL: exa                                                    | `[automated]` as `eza` from apt                                                                          |
| WSL: GVM and its apt dependencies                           | `[automated]` `install_gvm` and the `requirements` array                                                 |
| WSL: terra                                                  | `[automated]` `install_terra`                                                                            |
| WSL: `az`                                                   | `[automated]` `install_azure_cli`                                                                        |
| WSL: sqlite3, jq, age, inotify-tools                        | `[automated]` apt arrays                                                                                 |
| WSL: chezmoi                                                | `[automated]` by the `get.chezmoi.io` one-liner                                                          |
| Microsoft Azure Storage Explorer                            | `[automated]` `Microsoft.Azure.StorageExplorer`                                                          |
| Draw.io, NiceHash Miner                                     | `[manual]`, both still question marks on the checklist                                                   |

### Gaming

| Item            | Status                                              |
|-----------------|-----------------------------------------------------|
| Steam           | `[automated]` `Valve.Steam`                         |
| Battle.net      | `[manual]`, `Blizzard.BattleNet` commented out      |
| Epic Games      | `[automated]` `EpicGames.EpicGamesLauncher`         |
| EA App          | `[automated]` `ElectronicArts.EADesktop`            |
| GOG             | `[automated]` `GOG.Galaxy`                          |
| Ubisoft Connect | `[manual]`, `Ubisoft.Connect` commented out         |
| Mavis HUB       | `[manual]`                                          |

### Files

| Item                                            | Status                                                                                                           |
|-------------------------------------------------|------------------------------------------------------------------------------------------------------------------|
| Login to Microsoft account, OneDrive, Edge      | `[manual]`                                                                                                       |
| Fonts: Fira Code, MesloLGS NF                   | `[automated]` `windows-003-install-fonts.ps1`, `linux-004-install-fonts.sh.tmpl`, `android-003-install-fonts.sh.tmpl` |
| Restore backups                                 | `[manual]`                                                                                                       |
| `find . -name "*:Zone.Identifier" -type f -delete` | `[manual]`                                                                                                    |
