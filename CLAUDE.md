# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repository Is

Cross-platform dotfiles managed with **chezmoi** targeting three platforms: **Linux (Kali on WSL)**, **Windows 11**, and **Android (Termux)**. Secrets are managed via **1Password CLI** and sensitive files are encrypted with **age**.

The "build" is `chezmoi apply`. A CI pipeline validates templates, scripts, and platform logic.

## Quality Commands

```bash
make lint                           # shellcheck, Go template syntax, Python, PowerShell, YAML/JSON
make test                           # template rendering (mock op), .chezmoiignore logic, script order
make sast                           # gitleaks + semgrep secret/code scanning
make lint-shellcheck                # shell scripts only
make lint-templates                 # Go template syntax only
make test-template-render           # template rendering with mock 1Password
make test-chezmoiignore             # platform file inclusion logic
make test-script-order              # script dependency ordering
make test-modify-scripts            # modify script (merge) behavior
make test-remove-dependencies       # dependency removal library (tombstones, $HOME safety rail)
make test-remove-dependencies-windows # Windows removal script, failed removals reported (needs pwsh)
make test-install-dependencies-windows # Windows installer: detection by exact ID, failed installs reported (needs pwsh)
make test-prune-tmp-modcache        # $TMPDIR Go module cache pruning ($TMPDIR safety rail)
make test-shell-credentials         # 1Password credential/workspace loading and removal
make test-clipboard-shim            # Claude Code clipboard shim (Ctrl+V image paste)
make test-nvm-resolution            # NVM default-alias resolution in dot_zshenv
make test-zshrc-functions           # top-size, sentry-ds and rebuild-ocode in dot_zshrc: arguments, sudo, the work store, completion, the resolved build script
make test-sentry-setup              # the Sentry CLI setup scripts: the version floor sentry-ds needs, the upgrade, failing until it holds
make test-local-llm                 # the local model server: its settings, the window its unit allocates, the installer's gate
make test-opencode                  # OpenCode V2: the render on both platforms, the provider, the MCP shape, the reference
make test-tailscale                 # tailscale-up on bare metal and on WSL (Windows' client): the quiet pass, the login, sharing the model's server
make test-wsl-systemd               # systemd on WSL: the /etc/wsl.conf merge, the restart messages, installers that wait for it
make test-statusline                # Claude Code status line: with and without a login, no refresh without one, the token off argv
make test-claude-lsp                # language servers and their plugins: pins, order, the regular profile, the first apply
make test-omniroute-backup          # the OmniRoute stack's encrypted backups: the snapshot flow, retention, the installer's gate
make test-omniroute-image           # the custom OmniRoute image pin: the switch from upstream, --check, --tag, and failed lookups leaving the pin untouched
make test-ocode                     # the ocode fork build: skip paths, rebuilds, the running-ocode prompt, the dependency install, the pinned bun (cache, verified download, fallbacks), the ~/.bun/bin fallback, the bun installer and its PATH block
make test-terra-update              # terra update in both installers carries TERRA_ASSUME_YES=true
make test-yq                        # mikefarah's yq: the pin, the Python yq it replaces, the skip, the failures, the wiring
make test-export-keys               # the age keys fetched before every apply on Linux: the match, the fetch, failures, the WSL-only backup key
make test-export-key-windows        # the Windows chezmoi key export: the match, the fetch, a failed or wrong read (needs pwsh)
make test-install-fonts-windows     # the Windows fonts, per user: what is missing, what is installed, a failed download (needs pwsh)
```

## Essential Commands

```bash
chezmoi status                      # show managed files and their state
chezmoi diff                        # preview pending changes
chezmoi apply --dry-run             # test without applying
chezmoi apply                       # apply configuration to home directory
chezmoi apply --verbose             # apply with detailed output
chezmoi update                      # pull repo changes and apply
chezmoi edit ~/.zshrc               # edit a managed file
chezmoi add ~/.new-file             # add a new file to management
chezmoi add --encrypt ~/.secret     # add with age encryption
chezmoi cat ~/.ssh/config           # decrypt and display an encrypted file
chezmoi execute-template < file.tmpl  # test template rendering
chezmoi doctor                      # diagnose installation issues
```

## Chezmoi File Naming Conventions

| Prefix/Suffix       | Meaning                                                |
|---------------------|--------------------------------------------------------|
| `dot_`              | Becomes `.` in target (e.g., `dot_zshrc` → `~/.zshrc`) |
| `.tmpl`             | Processed as Go template before deployment             |
| `encrypted_*.age`   | Age-encrypted file, decrypted on apply                 |
| `run_before_*`      | Script runs before file application, on every apply    |
| `run_once_before_*` | Script runs once before file application               |
| `run_after_*`       | Script runs after every application                    |
| `run_onchange_after_*` | Script runs after application, only when its own content changes |
| `private_`          | File deployed with restricted permissions              |

## Platform Targeting

Platform-specific logic is handled in two ways:

1. **`.chezmoiignore`** — Uses inline Go templates to exclude files per OS (`eq .chezmoi.os "linux"`, `"windows"`, `"android"`)
2. **`.tmpl` files** — Go template conditionals inside configuration files

Platform-specific scripts in `.chezmoiscripts/` are prefixed: `linux-*`, `windows-*`, `android-*`.

### Platform Matrix

| Aspect     | Linux (WSL)                  | Windows                 | Android (Termux)                 |
|------------|------------------------------|-------------------------|----------------------------------|
| Shell      | Zsh + Oh My Zsh + p10k       | PowerShell + Oh My Posh | Zsh + Oh My Zsh + p10k           |
| Scripts    | `.sh`                        | `.ps1`                  | `.sh`                            |
| Docker     | Native                       | N/A                     | `termux-etc-seccomp` wrapper     |
| MCP config | `modify_dot_claude.json` (Context7 over HTTP, Chrome DevTools through npx) | N/A (no Claude Code) | `modify_dot_claude.json` and `dot_config/mcphub/` (Context7 over HTTP) |
| 1Password  | Native `op` CLI              | Native `op` CLI         | `termux-etc-seccomp` wrapper at `.local/bin/op` |

## Key Files

- **`.chezmoi.yaml.tmpl`** — Chezmoi config: 1Password and age encryption settings
- **`dot_gitconfig.tmpl`** — Git config with 1Password SSH signing, per-device SSH keys, platform-specific paths
- **`dot_zshrc.tmpl`** — Shell config: ZINIT plugins, version managers (GVM/NVM/Pyenv/SDKMAN/Cargo), Docker aliases, Kubernetes tools
- **`dot_zshenv.tmpl`** — PATH setup for version managers (critical for IDE integration)
- **`.chezmoiignore`** — Platform-conditional file exclusion rules
- **`.chezmoitemplates/`** — Shared template fragments (shared install functions, font installer, dependency removal, the Sentry CLI version floor, MCP server merge logic, username)

## Template Variables

Commonly used chezmoi template variables in this repo:
- `.chezmoi.os` — `"linux"`, `"windows"`, `"android"`
- `.chezmoi.hostname`, `.chezmoi.homeDir`, `.chezmoi.arch`
- `.chezmoi.kernel` — Used to detect WSL (`microsoft` in kernel name)
- `onepassword` — Fetch full item by name/UUID from 1Password (preferred — returns `.title` + `.fields`)
- `onepasswordRead` — Fetch a single scalar field by `op://` URI (use only for simple direct reads)

## Config Data Comes From `chezmoi init`, Never From Apply

`.chezmoi.yaml.tmpl` is rendered into `~/.config/chezmoi/chezmoi.yaml` by `chezmoi init`
only -- `chezmoi apply` and `chezmoi update` never re-render it -- so a key added under its
`data:` (like `deviceName`) does not exist on a machine until init runs there again. chezmoi
prints `config file template has changed, run chezmoi init to regenerate config file` at the
top of each apply, which is easy to lose above a long installer run, and
`chezmoi apply --force` silences it without regenerating anything. A Windows config written
in January from the template before `deviceName` existed stayed that way for months, hidden
behind the `.claude.json` failure that aborted every apply earlier in the same run.

`.chezmoiscripts/run_before_000-verify-chezmoi-config.tmpl` makes that gap loud. It renders
to nothing when every data key is present, so chezmoi never executes it, and otherwise
fails the apply before any installer with an instruction to run `chezmoi init`. **When adding
a key under `data:` in `.chezmoi.yaml.tmpl`, add it to that guard's list too.**
`make test-template-render` covers both directions.

## 1Password Template Pattern

Each device has a single **"Device: \<deviceName\>"** Secure Note in the `personal` vault. The note combines two storage mechanisms:

- **`notesPlain`**: lists references to external items (SSH keys, GPG keys, PEM certs, Docker registries) in `type:Item Name` format, one per line
- **Custom fields**: store credential and workspace values directly on the device note, with `type:name` labels (e.g., `cred:GH_TOKEN`, `ws:mine`)

Templates fetch this note (cached by chezmoi across all template files) and filter by type prefix.

**Type prefixes:**

| Prefix | Storage | Consumer |
|--------|---------|----------|
| `ssh`  | `notesPlain` entry referencing SSH Key item in `Private` vault | Chezmoi templates |
| `gpg`  | `notesPlain` entry referencing Secure Note in `Private` vault | Chezmoi templates |
| `pem`    | `notesPlain` entry referencing Secure Note in `Private` vault | Chezmoi templates |
| `docker` | `notesPlain` entry referencing Docker registry item in `Private` vault | Chezmoi templates |
| `cred`   | Field on device note (`cred:NAME` label, concealed value) | Runtime `op-loader` |
| `ws`     | Field on device note (`ws:NAME` label, text value) | Runtime `op-loader` |

**Device-note pattern with type filtering:**
```go
{{- $deviceNotes := "" -}}
{{- range (onepassword (printf "Device: %s" $deviceName) "personal" "my").fields -}}
  {{- if and (eq .label "notesPlain") (hasKey . "value") -}}
    {{- $deviceNotes = .value -}}
  {{- end -}}
{{- end -}}
{{- range splitList "\n" $deviceNotes -}}
  {{- $entry := . | trim -}}
  {{- if ne $entry "" -}}
    {{- $type := index (split ":" $entry) "_0" -}}
    {{- $name := trimPrefix (printf "%s:" $type) $entry | trim -}}
    {{- if eq $type "ssh" -}}
      {{- $item := onepassword $name "Private" "my" -}}
      {{- $f := dict -}}
      {{- range $item.fields -}}
        {{- if hasKey . "value" -}}
          {{- $_ := set $f .label .value -}}
        {{- end -}}
      {{- end -}}
      {{- $val := index $f "field name" -}}
```

**Always guard with `hasKey . "value"`** — some 1Password fields lack a `value` property; accessing it without a guard causes `map has no entry for key "value"`.

**When the loop emits code, keep a newline on both sides of each block.** A trailing `-}}`
eats every newline up to the next character, so an action right before a block's first line
glues that line onto whatever the previous iteration emitted last. In the Windows key
scripts, a `-}}` after the `warnf` turned a second `ssh:` entry into
`Set-Content … -Force# read the SSH public key…`, which PowerShell reads as a parameter named
`Force#` — only the last key was written. The fixture device note therefore carries **two**
entries of every type, and `make test-template-render` checks those scripts line by line.

**Do not use `onepasswordItemFields`** — it only returns section-level fields and misses built-in properties like `"public key"` and `"private key"` on SSH Key items. The `onepassword` + `dict`/`set` pattern accesses all fields and chezmoi caches the underlying `op item get` call across all template files automatically.

## Runtime Credential Lifecycle (Removal Needs a Manifest)

`cred:` and `ws:` fields are loaded at shell startup by `dot_scripts/linux-engineering-{shell-credentials,workspace-aliases}.sh` and cached in `~/.cache/op-{credentials,workspaces}.env` (mode `600`, 24h TTL). `reload-credentials` re-reads both.

**A rewritten cache cannot remove anything.** Once `export GH_TOKEN` has run, the value lives in the environment, not in the file — so deleting the field from the device note drops it from the cache while the variable survives in that shell and in every shell forked from it (tmux panes, IDE terminals, MCP subshells inherit the environment, never the cache).

Each successful load therefore writes the names it returned into `_OP_CRED_NAMES` / `_OP_WS_NAMES`, both in the cache file and in the environment:

| Half | Mechanism |
|------|-----------|
| The shell that reloads | `_op_prune_removed` in the loader scripts diffs the inherited manifest (plus the names the on-disk cache still assigns) against the fresh load, and unsets the difference |
| Shells that inherited the value | `dot_zshenv.tmpl` runs the same diff after sourcing the caches, which is what makes a newly opened terminal drop a credential deleted elsewhere |

**When touching this code, keep three invariants:**

1. **Never prune on a failed fetch.** A locked vault, a missing `op`/`jq`, and a deleted field all look identical — "not in the response". `_op_load_references` returns non-zero when it never reached 1Password, and callers must leave the environment alone; pruning there would wipe every credential during a brief outage.
2. **Never delete the caches to force a reload.** `reload-credentials` sets `_OP_RELOAD=1` to bypass the TTL instead, because the fetch reads the outgoing cache to recognise credentials exported by revisions that wrote no manifest.
3. **Keep the `.zshenv` prune off the hot path.** It runs on every shell, so it is guarded on a manifest that was both inherited *and* changed, and `_op_read_cache_names` returns through a global rather than command substitution — the Termux phantom-process budget makes avoidable forks expensive.

`make test-shell-credentials` covers all of this against a mock `op`.

## Logging Convention

All scripts and templates use a standardized `[prefix]` logging format to stderr:

```
[prefix] message              # informational (default)
[prefix] WARN: message        # non-fatal issues, skips
[prefix] ERROR: message       # fatal issues before exit
```

| Channel | How |
|---------|-----|
| Templates (`.tmpl`) | `warnf "[prefix] message"` — writes to stderr during rendering (do NOT add `\n`, chezmoi appends its own newline) |
| Shell scripts (`.sh`) | `echo "[prefix] message" >&2` |
| PowerShell (`.ps1`) | `Write-Host "[prefix] message"` |
| Modify-templates (JSON `modify_*`) | `warnf "[prefix] message"`, only when the file actually changes |

Existing prefixes: `gitconfig`, `ssh-config`, `allowed-signers`, `authorized-keys`, `docker-config`, `wakatime`, `age-recipients`, `android-ssh-keys`, `linux-gpg-keys`, `windows-ssh-keys`, `windows-pem-keys`, `wrapper`, `op-wrapper`, `gh-wrapper`, `acli-wrapper`, `golangci-lint-wrapper`, `claude-wrapper`, `export-key`, `extract-folders`, `clone-tools`, `configure-deps`, `ssh-known-hosts`, `copy-appdata`, `termux-config`, `fonts`, `kube-config`, `mcp-servers`, `claude-trust`, `claude-settings`, `claude-code-patch`, `ggshield-auth`, `ggshield-hook`, `jetbrains-themes`, `acli`, `send`, `credentials`, `workspaces`, `dev-toolkit`, `aws-cli`, `azure-cli`, `golangci-lint`, `sync-repo`, `install-deps`, `remove-deps`, `tmp-modcache`, `sentry-setup`, `claude-exec-shim`, `clipshot`, `ssh-agent-bridge`, `rustdesk`, `chezmoi-config`, `ollama`, `tailscale`, `chrome`, `claude-lsp`, `wsl-systemd`, `omniroute-backup`, `top-size`, `ocode`, `rebuild-ocode`

## Dependency Lifecycle (Removal Is Explicit)

This repository is a **sync**, not a bootstrapper. Deleting an `install_*()` function from a dependency installer only stops *new* machines from getting the tool — machines that already ran it keep it forever. chezmoi has no history of the source state and no concept of packages, so **both halves of a removal must be declared explicitly**.

| Half | Mechanism |
|------|-----------|
| Files orphaned in `$HOME` | `.chezmoiremove` (deleted on every apply; patterns are home-relative, `#` starts a comment) |
| Installed packages | `.chezmoiscripts/run_onchange_after_<platform>-*-remove-dependencies.*` tombstones |

**When removing a dependency, always do all three:**

1. Delete the `install_*()` function (or package-list entry) from the platform installer.
2. Add a `"<strategy>:<target>"` tombstone to the removal script of **every** platform that installed it, with a comment referencing the pull request that removed it. Not a commit hash from the feature branch: a rebase before merge rewrites it, which is how the `keychain` entries came to cite `9b19f46`, a commit that never reached `main`.
3. Add any orphaned config directory to `.chezmoiremove`.

Strategies live in `.chezmoitemplates/lib-remove-dependencies.sh` (shared by Linux and Android; Windows has its own inline set): `apt`, `gh_extension`, `npm_global`, `path`, `pipx`, `winget`. Every handler is idempotent and silent when the target is already absent.

A removal that leaves its target behind is reported (`WARN: failed to remove ...`), never counted as removed. The Windows handlers decide that by checking whether the package or path is still there, not by the uninstaller's exit code, which can be 0 when nothing was removed. The scripts still exit 0, so a failed removal is not retried until the tombstone list changes.

`remove_path` refuses any target outside `$HOME` — these scripts run unattended, so never widen that guard. `make test-remove-dependencies` covers it, and `make test-remove-dependencies-windows` covers the Windows script (it needs `pwsh`, which CI installs).

See `.docs/dependency-lifecycle.md` for the rationale, including why Nix/home-manager was evaluated and rejected (it cannot cover Windows-native or Termux).

## JSON Patching (Modify-Templates, Not Scripts)

`~/.claude.json`, `~/.claude/.claude.json`, `~/.claude/settings.json` and mcphub's
`servers.json` are merged into, never overwritten, by `modify_` files that are chezmoi
**modify-templates**: chezmoi evaluates them itself, with the file's current content in
`.chezmoi.stdin`, and writes back what they output. They used to be bash scripts that
ran embedded Python, and on Windows they could never start: chezmoi picks an interpreter
from the file extension (`.json` has none), Windows has no `#!`, and the apply aborted at
`fork/exec …..claude.json: %1 is not a valid Win32 application`.

| Rule | Why |
|------|-----|
| The file carries `chezmoi:modify-template` and has **no** `.tmpl` suffix | With `.tmpl`, chezmoi renders it as an ordinary template first, where `.chezmoi.stdin` does not exist |
| Shared logic is pulled in with `includeTemplate`, not `template` | `.chezmoitemplates/` is not associated with a modify-template, so `{{ template … }}` fails with `not defined`. `.chezmoi.targetFile` is missing there too, which is why the MCP library takes the file name as an argument |
| Output `.chezmoi.stdin` unchanged when nothing managed is missing | Go maps keep no order, so `toPrettyJson` emits sorted keys. Passing the content through keeps the layout Claude Code wrote, and a real change is the only time a file is re-serialised |
| Compare with `toJson`, never `eq` on decoded values | A missing key decodes to `""`, and `eq` between a string and a bool is an error rather than `false` |
| Invalid JSON fails the template | The old scripts started from `{}` and replaced the file; failing leaves it for a person to repair |

`make test-modify-scripts` runs each one through `chezmoi cat` in a sandbox, and fails when
any `modify_` file that chezmoi resolves for Windows is not a modify-template.

## MCP Servers

`.chezmoitemplates/lib-modify-mcp-servers.tmpl` declares the user-scope MCP servers once, and
`modify_dot_claude.json` and mcp-hub's `dot_config/mcphub/modify_servers.json` merge them in.
They come in groups, and `$groupsByOs` names the groups each platform gets:

| Group | Servers | Linux | Android |
|-------|---------|-------|---------|
| `remote` | `context7` (HTTP) | yes | yes |
| `browser` | `chrome-devtools` (npx) | yes | |

Windows gets no `~/.claude.json` at all: Claude Code is no longer installed there.

**Keep these:**

1. **A placeholder is a bare `${NAME}`.** Claude Code also expands `${NAME:-default}`, but
   mcp-hub reads the same list and looks that form up as a variable named `NAME:-default`, which
   in its default strict mode keeps the server from starting even when `NAME` is set. An unset
   `${NAME}` reaches the server as literal text, and `claude mcp list` reports `Missing
   environment variables`. For Context7 that means `Invalid API key` on every call until the
   `cred:CONTEXT7_API_KEY` field exists -- never a silent fall back to the anonymous tier, which
   is where Upstash appended instructions to install its CLI to query results in May 2026
   (upstash/context7#2663).
2. **No placeholder on a command line.** A value in `command` or `args` is readable by any local
   user in `/proc/<pid>/cmdline`, so tokens go in `env` (stdio) or `headers` (HTTP), which Claude
   Code fills in itself. Context7's README puts its key in `--api-key`; its local server reads
   `CONTEXT7_API_KEY` from the environment too.
3. **Prefer a vendor's remote server.** It starts no process -- a stdio server is spawned per
   Claude Code session, and on Termux each one counts against the phantom-process budget -- and
   runs no npm code on the machine. Context7's local server sends the same queries to the same
   backend, so it would buy no privacy.
4. **An npx server is pinned when its releases carry provenance.** `chrome-devtools-mcp` is
   published from GitHub Actions with SLSA provenance and bundles every dependency, so a pinned
   version is one attested tarball, while `@latest` runs whatever was published last at each
   session start. Bump the pin by hand; the next apply prints `[mcp-servers] set chrome-devtools`.
5. **Chrome DevTools runs a throwaway, headless browser.** Each flag answers a failure or a leak:

   | Flag | Why |
   |------|-----|
   | `--isolated` | A temporary profile per session. The default profile admits one browser, so a second concurrent session would fail, and logins would carry across projects |
   | `--headless` | No display needed, so tmux, SSH and the tailnet work as a WSLg desktop does |
   | `--executable-path /opt/google/chrome/chrome` | Google's package, from `run_onchange_after_linux-011-setup-chrome.sh`. Left to search, Puppeteer on WSL goes on to Windows' Chrome through `cmd.exe` and cannot drive it |
   | `--redact-network-headers` | Every header outside DevTools' allowlist reads `<redacted>` -- `Authorization` and cookies, but custom `X-` headers too -- so the app's credentials stay out of the transcript. Response bodies are not redacted |
   | `--no-usage-statistics`, `--no-performance-crux`, `CHROME_DEVTOOLS_MCP_NO_UPDATE_CHECKS` | Its three calls home: usage statistics to Google (on by default), page URLs to the CrUX API, and a daily npm check that a pin turns into noise |

   It is Linux only: Termux has no supported Chrome, and Windows gets no MCP servers. It drives
   Google's package rather than Kali's `chromium`, which trailed the stable channel by five
   releases when this was written -- this is the browser Claude points at pages nobody vetted.
6. **Removing a server is explicit.** The merge never touches a server it does not manage, so a
   server deleted from its group would stay in every existing file. Its name goes into
   `$retiredByOs` for the platforms it was set on, and the next apply deletes it, printing
   `[mcp-servers] removed …`. Any entry under that name on those platforms was overwritten on
   every apply, so it is the repository's to delete; the same name elsewhere belongs to the user
   and stays. `github`, `azure-devops`, `sonarqube` and `kubernetes` were retired this way on
   2026-10-14 in favour of their CLIs, and `dot_claude/modify_settings.json` retires the
   `mcp__github__*` rule that pre-approved the first one's tools on Android.

To watch the browser or read the redacted headers in one project, add a server of the same name
at local scope there, keeping the rest of the flags:
`claude mcp add --scope local chrome-devtools -- npx -y chrome-devtools-mcp@1.10.1 --executable-path /opt/google/chrome/chrome --isolated --no-usage-statistics --no-performance-crux`.
Local scope replaces the user-scope entry whole, and it lives under the project's key in
`~/.claude.json`, which the merge never writes. `/mcp` switches a server off per project, a
choice Claude Code also keeps there, so an apply leaves it alone.

**Evaluated and left out** (2026-10-14), so that neither comes back without a new reason:

- **DBHub** (`@bytebase/dbhub`). Databases are per project, so a user-scope server fails at
  startup in every other session -- or, finding a DSN in the project's `.env`, connects
  read-write. Its read-only mode is a keyword filter over a per-transaction read-only mode, and it
  had three CVEs in 2026, two of them read-only bypasses. Let Claude use the database's own CLI as
  a read-only role, or commit a pinned server to that project's `.mcp.json`.
- **Serena** (`oraios/serena`). 2.0.0 defaults to an unsandboxed Python REPL that a repository's
  own `project.yml` can select, four code-execution fixes landed in four months (one still
  unreleased), it reports usage home at every start, and it writes `.serena/` into each
  repository; its language-server setup raises `Unknown platform` on Termux. Claude Code's LSP
  plugins (`gopls-lsp`, `pyright-lsp`, `typescript-lsp`, `jdtls-lsp`) cover the navigation it
  offers.

`make test-modify-scripts` covers what each platform gets, that mcp-hub receives the same list,
invariants 1 and 2 across every platform, and the retirements in 6.

## Claude Code Language Servers

Claude Code's `LSP` tool -- definitions, references, hover, symbols, call hierarchy, and the type
errors it reports after each edit -- does nothing until a plugin names a language server and the
server is on `PATH`. On Linux, `.chezmoiscripts/run_onchange_after_linux-012-setup-claude-lsp.sh`
installs both halves:

| Plugin (`claude-plugins-official`) | Server it starts | Installed as |
|------------------------------------|------------------|--------------|
| `gopls-lsp` | `gopls` | `go install` into `~/.local/bin` |
| `typescript-lsp` | `typescript-language-server --stdio`, with `typescript` 6.x | `npm install -g` into NVM's default Node |
| `pyright-lsp` | `pyright-langserver --stdio` | `npm install -g` into NVM's default Node |

**Keep these:**

1. **The plugins are installed, not just enabled.** An `enabledPlugins` entry alone installs
   nothing -- on a fresh profile `claude plugin list` stays empty -- so the script runs
   `claude plugin install … --scope user`, which writes the entry too. A fresh profile knows only
   the built-in directory, so the script adds the `claude-plugins-official` marketplace first. The
   ids are that marketplace's because aifiles' `settings.json` and earlier project-scope installs
   use them, and two ids for one plugin would start two copies of its server.
2. **`gopls` lives in `~/.local/bin`.** `dot_zshenv.tmpl` puts only the newest Go's GVM pkgset on
   `PATH`, so a plain `go install` would vanish at the next Go upgrade.
3. **TypeScript stays on 6.x.** typescript-language-server drives tsserver, and TypeScript 7 --
   the native port, npm's `latest` since July 2026 -- ships none. A project's own
   `node_modules/typescript` still wins; the global one is the fallback.
4. **Every server is pinned** at the top of the script, so bumping one is an edit there, which is
   also what reruns the script on the next apply. npm runs with `--ignore-scripts`: none of these
   packages has an install script.
5. **No `-y` and no terminal.** None of these plugins runs a command to install; one that started
   to fails here instead of running unattended.
6. **The regular profile only.** The script unsets `CLAUDE_CONFIG_DIR`, so an apply run from inside
   a session on another profile cannot put plugins into that profile.
7. **A failure fails the apply.** A server that does not install keeps its plugin out, and the run
   exits non-zero so the next apply retries it; a machine without `claude` fails the same way.
8. **aifiles mirrors the result.** Where aisync runs, `aisync pull` rewrites `settings.json` from
   aifiles' copy, asking first when the live file differs, and accepting drops whatever only the live
   file has. That copy therefore lists the same three plugins and the marketplace: add a plugin in
   both places.

It is Linux only. Windows work happens inside WSL. On Termux, Claude Code starts a server itself,
not through a shell, with `LD_PRELOAD` parked (see "Android Performance"), so the two servers that
are `#!/usr/bin/env node` scripts would hit the `bad interpreter` failure described there --
unverified on a device, which is why it is not attempted. Java's `jdtls-lsp` is left out: Eclipse
JDT LS needs a Java 21 runtime and starts a JVM in every session that opens a `.java` file.

`make test-claude-lsp` covers 1 and 3 to 7 against stubbed `go`, `npm` and `claude`, and the first
apply's bash, which has to find GVM's newest Go and NVM's default Node on its own.

## Shared Install Library

`.chezmoitemplates/lib-install-deps.sh` holds the install functions whose body is correct on both Linux/WSL and Android without a conditional: `command_exists`, `install_oh_my_zsh`, `install_sdkman`, `install_nvm`, `install_fly_cli`, `install_sentry_cli`, `install_neon_cli`, plus the `run_remote_installer` helper they use to download an installer script to a temp file and run it (never pipe `curl` into `bash`; without `pipefail` an HTTP error page runs silently). Both dependency installers pull it in with `{{ template "lib-install-deps.sh" }}`, which is the only reason the Linux installer is a `.sh.tmpl`.

Keep platform-specific provisioning in the platform installers: apt repositories versus binary downloads (`gh`, `kubectl`), upstream install scripts versus source builds (`terra`, `dev-toolkit`, `aisync`), pyenv versus Termux's native Python. A function moves into the library only when the same body is right on both platforms. The library is pure bash (no template directives), so `make lint-shellcheck` lints it as a plain `.sh` file, and its messages use the `[install-deps]` prefix.

Oh My Zsh is installed with `--unattended` on both platforms, so the login shell is switched explicitly right after it, and only when the install succeeded: `usermod` on Linux, Termux's `chsh -s zsh` on Android. Every remote installer in the library (Oh My Zsh, SDKMAN, NVM) goes through `run_remote_installer`, which forwards extra arguments to the script; do not reintroduce `sh -c "$(curl ...)"`, because a failed download becomes an empty command that exits 0. On Termux `install_nvm` keeps the native `nodejs` package and only enables corepack; the check is on Termux's prefix, not on where `npm` resolves from, because WSL exposes Windows' `npm` through PATH interop.

## Flutter SDK (Symlinks, Not PATH)

Both dependency installers carry an `install_flutter`, and the two bodies are different on purpose — they stay out of `lib-install-deps.sh` for the reason that file states.

| Platform | Source | Where | Reached through |
|----------|--------|-------|-----------------|
| Linux/WSL | The official Linux x64 tarball. `releases_linux.json`'s `current_release.stable` names the release, which carries the archive path and its SHA-256, so the download is pinned to what Google published rather than to a version this repository would have to bump — the same shape as `install_gvm` resolving Go from go.dev. | `~/.local/share/flutter` | `~/.local/bin/flutter` and `~/.local/bin/dart`, symlinks into the SDK |
| Android/Termux | Flutter publishes no Linux arm64 host SDK. `GeneralKaos666/flutter-for-termux` packages mumumusuc's bionic cross-build as a Termux `.deb`; it is pinned to a version and a SHA-256 that is **integrity-only — an accepted, recorded risk**: computed from the inspected file, and corroborated by the package's own identity (a git checkout at tag `3.47.5` = `6a19cca5`, engine `af7e796e16`, Dart 3.13.4 — all equal to Google's release). `Pre-Depends: x11-repo` is why the installer enables that repository first. | `$PREFIX/opt/flutter` | Two bash wrappers in `~/.local/bin` that name Termux's bash, because the SDK's own launchers are `#!/usr/bin/env` scripts and that path needs termux-exec to start |

**Expect the Android pin to need bumping: upstream replaces the asset under a fixed tag.** The first pinned digest stopped matching a day after it was committed — GitHub's API reports the `3.47.5` asset created `2026-09-20T02:02Z` against a release published `2026-09-19T02:47Z`, and the two releases before it show the same gap (`3.47.4` published 09-12, asset 09-18; `3.47.3` published 09-10, asset 09-11), where everything up to `3.47.2` had its asset within seconds of publishing. The replacement carried an identical engine revision, framework commit and Dart version, so it is a CI rebuild whose tar/xz bytes are not reproducible rather than a change of content — but the digest moves either way, so `does not match the pinned SHA-256` is the **expected** failure mode here, not a discovery. Re-run the in-package corroboration before bumping; a fresh download proves only that GitHub served what GitHub currently holds. **Nothing bounds the risk of a bad bump**: the control archive carries no maintainer scripts, so `dpkg` runs nothing, but the installer executes the payload itself moments later (`flutter --version`, `precache --web`) and puts `dart`/`flutter` on `PATH` for every later shell. The corroboration is the whole of the defence, which is why it is not optional.

**Why links in `~/.local/bin` and not a PATH entry in `dot_zshenv.tmpl`.** `~/.local/bin` is prepended by `.zshenv` *and* again by `.zshrc`, independently, so a PATH entry for the SDK would have to win against it twice — and a `dart` in `~/.local/bin` that is not the Flutter one is exactly what `flutter doctor` warns about: two Dart SDKs whose versions drift. The SDK's launchers resolve symlinks before locating the SDK (`follow_links` in `bin/flutter`), so the links are the supported shape, and an existing `~/.local/bin/dart` pointing anywhere else is repointed with a line saying so.

**The version marker is `bin/cache/flutter.version.json`, never the top-level `version` file.** 3.47 ships with `omit-legacy-version-file`, so that file does not exist, and an empty read sent every apply back through the 1.4 GB download (measured: 3m33s per re-run). The marker is dropped and rebuilt after `flutter upgrade`, because the tool rewrites it only when the git revision changed — a marker stale for any other reason would otherwise trigger the upgrade branch on every apply.

**The package cannot unpack until `$PREFIX/share/flutter` exists.** Its data archive names `usr/share/flutter/manifest.json` but carries no directory entry for that parent, and dpkg creates no implicit parents — it extracts in archive order — so the unpack aborts with `unable to create '…/manifest.json.dpkg-new' …: No such file or directory`, which apt then reports as nothing but `dpkg returned an error code (1)` with the real line scrolled off above a wall of `Unpacking …`. `install_flutter` therefore `mkdir -p`s it before handing the file to apt. The archive orphans three further parents (`$PREFIX/bin`, `$PREFIX/etc/profile.d`, `/data`), all of which a Termux install already has; the set is a property of the pinned bytes rather than of the version, so re-derive it when bumping the pin with the one-liner in the comment at that `mkdir`.

**Android is verified on a device (2026-09-20), up to `flutter --version`.** It reports framework `6a19cca564`, engine `af7e796e16` and Dart 3.13.4 — the same triple the pin was corroborated against — after a first run that builds the flutter tool from source and resolves its dependencies (~2 min, network). That run is also what writes `bin/cache/flutter.version.json`, so the version marker does not exist between the `apt install` and the first successful launch — which is why the cached `.deb` is deleted only once that launch answers, and not on the line after `apt install` where the `rm` first sat. An apply interrupted in that window, or one where `flutter --version` fails outright, re-installs from the file instead of re-fetching 615 MB. `precache --web` and the `~/.local/bin` wrappers remain unexercised. The function was written from `dpkg-deb -I`/`-c` of the package (no maintainer scripts; 21,475 files; a bionic Dart VM, so no termux-etc wrapper; the `linux-arm64` engine including `flutter_tester`, and no web SDK, which `precache --web` fetches). `flutter --version` is the hard check; `precache --web` is reported and not fatal, because an artifact the custom engine cannot fetch would fail every apply forever. Termux's own `dart` package sits in `languages` as the baseline for `dart format` whether or not the SDK starts. Flutter's bundled `dart` shadows it through `~/.local/bin` only after the SDK answered.

## yq Is mikefarah's, Not Kali's

`make lint-syntax` and CI validate YAML with `yq eval`, the syntax of
[mikefarah's yq](https://github.com/mikefarah/yq). Kali's apt package named `yq` is a different
tool -- kislyuk's Python wrapper around jq (`yq 3.x`, shipping `xq` and `tomlq` too) -- which has
no `eval`, so on a machine that took `yq` from apt every YAML file failed the lint whatever its
content.

| Half | Mechanism |
|------|-----------|
| Install the right one | `install_yq` in the Linux installer downloads the pinned release into `~/.local/bin/yq`, checks it against a SHA-256 pinned per architecture, and skips only when that file already reports the pinned version -- `command -v yq` would find the Python one and skip |
| Drop the wrong one | `"yq"` is out of the apt list, and an `apt:yq` tombstone removes the package where it is installed (it needs passwordless sudo, as every `apt:` entry does) |

**Do not put `yq` back into the Linux apt list.** Termux's `yq` package is mikefarah's, so Android
keeps it from apt, and Windows installs no yq at all. CI pins its own copy in
`.github/workflows/validate.yaml`. To bump the installer's pin, take both builds' SHA-256 from the
release's `checksums` file, whose columns `checksums_hashes_order` names. `make test-yq` covers the
install against a stubbed `curl`, with the Python yq on PATH.

## One Interpreter Per Python CLI (pipx, Not pip)

On Linux/WSL, every Python **application** this repository installs goes through
pipx, never `pip install`. `install_pipx_app` in
`run_once_before_linux-002-install-dependencies.sh.tmpl` is the entry point for every
application that has to be migrated out of the shared pyenv environment;
`install_azure_cli` and `install_oci_cli` are one line each on top of it.

`install_ggshield` is the deliberate exception, and the only one: it calls
`python -m pipx install` / `python -m pipx upgrade` directly, because it was never
`pip install`ed (there is nothing to migrate) and it re-upgrades on every apply,
which `install_pipx_app` does not express. A new Python CLI goes on
`install_pipx_app` unless it needs that upgrade-on-every-run behaviour — do not add
a third way of installing one.

The reason is that pip resolves each command against only that command's
dependency graph — it does not look at unrelated distributions already present in
the environment. Two applications in one interpreter therefore share a single
dependency namespace, and the second install silently moves a pin the first one
depends on, reporting the damage only after writing it:

```
ERROR: pip's dependency resolver does not currently take into account all the
packages that are installed. [...] msal 1.35.0b1 requires cryptography<49,>=2.5,
but you have cryptography 50.0.1 which is incompatible.
```

That was `pip install oci-cli` pulling `cryptography` past the bound azure-cli's
`msal` declares. **Do not fix a collision like that by pinning it.** The pin holds
until the next release moves, and the same environment had already produced a
second one (`websocket-client 1.9.0` against azure-cli's `~=1.8.0`). Separate
venvs remove the shared namespace that produces them.

Three things about the migration are load-bearing, each of them a way this fails
quietly rather than loudly:

| Rule | Why |
|------|-----|
| pipx install first, remove the shared-environment copy second | A failed download then leaves a working CLI behind instead of none |
| Verify the entry point resolves *into* the pipx venv, and `--force` when it does not | pipx refuses to overwrite a command it does not own and reports that as a note, not a failure — so the package installs while its command goes on resolving elsewhere. `~/.local/bin/oci` was such a squatter, left by Oracle's `install.sh` |
| An unreadable pipx layout fails verification, never skips it | Guarding the check on a non-empty `PIPX_BIN_DIR` would turn "cannot verify" into "verified", and the uninstall below would then remove the only working copy — the exact outcome the check exists to prevent, reported as success |
| A failed `pip uninstall` is fatal, not a warning | The shared environment keeps its console script and `pyenv rehash` keeps the shim, so every later shell runs the conflicted copy while the script claims isolation |
| `pyenv rehash` after the `pip uninstall` | `$PYENV_ROOT/shims` sits ahead of `~/.local/bin` on PATH, so a stale shim keeps shadowing the pipx entry point and the machine goes on running the conflicted copy |

**Remove only the distribution that owns the console scripts** (`azure-cli`,
`oci-cli`) — those are what `pyenv rehash` turns into shims. Everything else the old
route pulled in stays behind as an orphan, because uninstalling a closure risks
taking packages other tools still import. `oci` is the clearest case: it is the
Oracle SDK, importable by user code, owns no console script, and removing it would
buy nothing.

A `return 1` from any of this is invisible on its own — the installer has no
`set -e`, so execution falls through and the last command decides the exit status.
The verified installers are therefore called through `verify`, which collects
failures and exits non-zero at the end: collecting keeps one failure from skipping
the dozen installers after it, and the non-zero exit is what makes the failure
self-healing, since chezmoi records a `run_once_` script's state only on success and
retries the whole installer on the next apply.

Android still uses `pip install` for both CLIs. Its installer carries build
workarounds that live in the shared environment — a pre-built `crc32c` wheel, a
patched `psutil` source tree, `SODIUM_INSTALL=system` — none of which survive into
a fresh pipx venv unmodified. Moving Termux over is its own change.

## NVM Resolution Must Agree With NVM

`dot_zshenv.tmpl` picks the Node version for every shell by resolving NVM's
`default` alias itself, because `nvm.sh` is too slow to source on every shell
start. That resolution has to reach the same version the real `nvm` would.

**"Newest installed" is not that version.** NVM's aliases form a chain —
`default` → `lts/*` → `lts/<codename>` → `vX.Y.Z` — and a machine that ever
installed a non-LTS Current release keeps it in `versions/node`, where a version
sort ranks it above the LTS the chain points at.

The consequence is invisible, which is what makes it worth a test. Global npm
packages live inside the active version's tree, so the dependency installer (which
runs the real `nvm`) puts `sentry` and Claude Code under the LTS, while a shell that
picked the higher Current release sees none of them. Every one of those
CLIs is installed correctly and missing from PATH, and nothing anywhere reports an
error — `install_codex_cli` had been running `npm install -g @openai/codex`
successfully into a tree the user's shell never looked at.

Two halves keep it fixed, and both are needed:

| Half | Mechanism |
|------|-----------|
| The shell picks what NVM picks | `dot_zshenv.tmpl` follows the alias chain to a concrete version (with a hop budget, since `nvm alias` permits cycles), honours `system` by leaving PATH alone, and falls back to the newest installed version only when resolution genuinely fails |
| An LTS bump carries the CLIs with it | `install_nvm` passes `--reinstall-packages-from` the current version, since a new major otherwise starts with an empty global tree. It is omitted on a first install, where `nvm current` prints `none`/`system` and nvm aborts on such a source |

`make test-nvm-resolution` covers the resolver, including the exact shape that
produced the bug: an LTS and a newer Current release installed side by side.

## Important Timing Constraints

Dependency installation scripts (`.chezmoiscripts/run_once_before_*-install-dependencies.*`) take **45-120 minutes**. Never cancel them mid-execution. Use timeouts of 120+ minutes when running full installations.

### Android Wrapper Timing

On Android, tool wrappers (`op`, `gh`) **must be `run_once_before` scripts**, NOT chezmoi-managed files under `dot_local/bin/`. This is because `run_once_before` scripts execute before chezmoi applies managed files. The install-dependencies script (`run_once_before_android-002`) calls `op` and `gh` during installation — if these wrappers were chezmoi-managed files, they wouldn't exist yet when the install script runs, causing crashes.

The wrapper scripts follow a strict execution order:
1. `android-001-create-wrapper.sh` — generic `termux-etc-seccomp` wrapper (all tool wrappers depend on this)
2. `android-001a-create-op-wrapper.sh` — `op` wrapper (needed by chezmoi templates)
3. `android-001b-create-gh-wrapper.sh` — `gh` wrapper (backs the `gh_linux_arm64` binary installed in step 7)
4. `android-001c-create-golangci-lint-wrapper.sh` — `golangci-lint` wrapper (backs the `golangci-lint_linux_arm64` binary installed in step 7)
5. `android-001d-create-acli-wrapper.sh` — `acli` wrapper (backs the `acli_linux_arm64` binary installed in step 7)
6. `android-001e-create-claude-wrapper.sh` — `claude` wrapper for Claude Code's `linux-arm64-musl` build (handles the background `patchelf`-aware auto-updater; first-time bootstrap is still manual via `examples/claude-code.md` in `rios0rios0/termux-etc-redirect`) It parks `LD_PRELOAD` in `TERMUX_ETC_LD_PRELOAD` instead of dropping it (see below) and takes `termux-wake-lock` before the `exec`. It also writes `~/.local/bin/claude-zsh`, the `CLAUDE_CODE_SHELL` launcher that restores the parked value before each tool-call zsh starts (see below).
7. `android-002-install-dependencies.sh.tmpl` — installs binaries and extensions

The generic `termux-etc-seccomp` wrapper is the only exception — it exists as BOTH a bootstrap script (for timing) AND a chezmoi-managed file (`dot_local/bin/executable_wrapper`) to keep it updated on subsequent applies.

## Android Performance (Termux)

Android 12+ includes a **Phantom Process Killer** that enforces a system-wide limit of ~32 forked child processes. Claude Code spawns many Node.js children, so running 3+ sessions causes `[Process completed (signal 9)]` — this is SIGKILL from the phantom killer, not OOM.

**Fix (Android 14+, no root required):** Enable `Settings > System > Developer Options > "Disable child process restrictions"`.

**Supplementary:** Run `termux-wake-lock` to prevent deep sleep. Use `tmux` instead of multiple Termux tabs to consolidate process trees.

**Environment tuning** (set in `dot_zshenv.tmpl`, Android-only):
- `UV_THREADPOOL_SIZE=16` — increases Node.js libuv thread pool from default 4, critical for Claude Code I/O
- `MALLOC_ARENA_MAX=2` — reduces glibc memory arena fragmentation on mobile
- `DBUS_SESSION_BUS_ADDRESS=disabled:` — blocks D-Bus session autolaunch. Without it, tools run through `termux-etc-seccomp` (`op`, `gh`, `acli`, `claude`) leak a `dbus-daemon --session --fork` that reparents to PID 1 and is never reaped, silently consuming the ~32-process phantom budget until any new subprocess trips the killer. `op` is the likeliest source (leaked daemons appeared in the same second as its `op-daemon.pid`), but the guard covers every wrapped tool

**`LD_PRELOAD` contract with `termux-etc-mount`:** the musl Claude binary cannot load Termux's bionic preload shims, so the wrapper and `termux-etc-mount` both move `LD_PRELOAD` to `TERMUX_ETC_LD_PRELOAD` before the `exec`. Two things hand it back, and each covers a case the other cannot, because an export from inside a running shell reaches only that shell's children, never the shell itself:

| Where the shims come back | Mechanism |
|---------------------------|-----------|
| In the tool-call shell itself | The wrapper exports `CLAUDE_CODE_SHELL=~/.local/bin/claude-zsh` (both files come from `001e`). Claude Code accepts the override because the path contains `zsh` and is executable, and derives the shell type and rc file from that string; the launcher restores the variable and `exec`s the real zsh, so `termux-exec` is mapped before the shell's first `execve`. This is what lets a tool call exec `sentry` or any other npm bin directly: those keep their `#!/usr/bin/env node` shebang, and the kernel resolves it only through the caller's preload. The launcher also drops the `NODE_EXTRA_CA_CERTS` the wrapper sets for Claude's own musl Node, which bionic Node never needs and the Sentry CLI warns about on every run |
| In everything a shell spawns | The Android block of `dot_zshenv.tmpl` re-exports the parked value (falling back to `termux-exec` alone when nothing was parked). On its own this half fixed `make` targets and pipelines scripts — children of the shell — but not a script exec'd straight from the tool call, which failed with `bad interpreter: /usr/bin/env` while `zsh -c 'sentry --version'` worked. It stays for a `termux-etc-mount` run by hand, an SSH login and an older wrapper |

Keep the variable name in step with `rios0rios0/termux-etc-redirect`; a `CLAUDE_CODE_SHELL` already in the environment wins over the launcher.

**The other half of that contract — `claude-exec-shim`:** restoring `LD_PRELOAD` in the tool-call shell re-breaks the one thing that runs the musl binary *from* that shell. Claude Code appends its own `grep` and `find` functions to the shell snapshot it sources into every tool call, and both run the Claude Code binary itself under another `argv[0]` (`ARGV0=ugrep "$CLAUDE_CODE_EXECPATH" …`, `ARGV0=bfs …`), because that binary is multi-call and dispatches on `argv[0]` alone. `$CLAUDE_CODE_EXECPATH` points straight at the musl build, so with `LD_PRELOAD` back every `grep` and `find` in a tool call exits 127 with eleven `symbol not found` lines. Three properties decide the fix:

| Property | Consequence |
|----------|-------------|
| The snapshot's functions are appended *after* `~/.zshenv` is sourced | Defining `grep`/`find` in an rc file cannot win — the snapshot's definitions always override them |
| The functions read `$CLAUDE_CODE_EXECPATH` at call time, and `~/.zshenv` runs before the snapshot | The path they `exec` is the only lever, so the Android block repoints it |
| The kernel replaces `argv[0]` with the interpreter path when it runs a `#!` file | A wrapper *script* cannot sit in between: `ugrep` would be lost and the binary would start as the Claude CLI. Only a real executable passes `argv` through untouched |

So `.chezmoiscripts/run_after_android-007-build-claude-exec-shim.sh` compiles a ~30-line C program to `~/.local/bin/claude-exec-shim`, and `dot_zshenv.tmpl` points `$CLAUDE_CODE_EXECPATH` at it while parking the real path in `TERMUX_CLAUDE_EXEC_TARGET`. The shim parks `LD_PRELOAD` under the same `TERMUX_ETC_LD_PRELOAD` name and `execv`s the target with `argv` untouched. It is the `claude` wrapper's job done at a level where `argv[0]` survives — the wrapper stays in charge of the CLI itself (`termux-etc-mount`, wake lock, updates), which the shim deliberately does not do, because `ugrep` and `bfs` are leaf processes that need no `/etc` redirection.

Both guards in the `.zshenv` block matter: a shell nested under a tool call inherits the repointed value and must not park the shim as its own target, and a missing shim (an apply that has not built it yet) must leave `$CLAUDE_CODE_EXECPATH` alone. `clang` is why this is a `run_after_` script rather than a `run_once_before_` wrapper — it is installed by `run_once_before_android-002`, so the build cannot happen before it.

**Diagnosing a phantom kill:** count forked children with `ps -A -o pid,ppid,cmd | grep com.termux | wc -l`. At ~30 you are saturated regardless of free RAM — check `free -m` to rule out real memory pressure, then look for orphans (`ppid == 1`) that should have been reaped.

**Manual Android settings:** Exclude Termux from battery optimization (`Unrestricted`), set animation scales to `0.5x`, enable RAM Plus if available.

### Never Let a Go Module Cache Land in `$TMPDIR`

Termux clears `$TMPDIR` from `TermuxService.onDestroy()`. That routine collects one stack trace per entry it fails to delete and then stringifies the whole batch, so a directory full of undeletable files turns app shutdown into an `OutOfMemoryError` — the heap growth limit is 256 MB and ~16k failures produced a 98 MB string.

Go module caches are exactly that kind of directory: entries are written as `0400` files inside `0500` directories, and unlinking a child needs its *parent* writable, so `rm -rf` fails with `EACCES` on every one. Anything cleaning `$TMPDIR` hits the same wall.

They get there because Go derives `GOMODCACHE` from `GOPATH`, and the pipelines Go scripts set `GOPATH="$(pwd)/.go"` when it is unset. Run `make test` with a cwd under `$TMPDIR` — Claude Code scratchpads live at `$TMPDIR/claude-<pid>/...` — and the cache is created there.

| Half | Mechanism |
|------|-----------|
| Prevention | `dot_zshenv.tmpl` exports `GOMODCACHE="$HOME/go/pkg/mod"`, so no `GOPATH` a script picks can move the cache |
| Cleanup | `.chezmoiscripts/run_after_android-005-prune-tmp-modcache.sh` chmods and removes any `*/pkg/mod` still found under `$TMPDIR` |

Both are needed: the pin cannot retroactively remove caches left by older revisions, nor reach a tool that exports its own `GOMODCACHE`. When deleting one by hand, always `chmod -R u+w` first.

**Diagnosing it:** `find "$TMPDIR" ! -writable | wc -l`. Anything in the thousands will crash Termux on exit. A telltale sign in the crash report is an *identical* allocation size across separate crashes — the file set is unchanged, so the string is deterministic.

## Clipboard Images on Termux (Ctrl+V)

Claude Code reads a clipboard image on Linux by shelling out, with `shell: true`, to exactly two
commands — there is no native clipboard binding and no `DISPLAY` gate on the read path:

```
xclip -selection clipboard -t TARGETS   -o | grep -E "image/(png|jpeg|jpg|gif|webp|bmp)"
xclip -selection clipboard -t image/png -o > $TMPDIR/claude_cli_latest_screenshot.png
```

Neither `xclip` nor `wl-paste` can ever work here: Termux has no X11 or Wayland display, and
Android's clipboard cannot hand a bitmap across the app sandbox at all. Termux:API is not a way
round it either — `termux-clipboard-get` returns text only. So Ctrl+V always reported
"No image found in clipboard".

Because the lookup is a plain `PATH` resolution inside `/bin/sh`, the fix is a **shim**, not a port:
`dot_local/bin/executable_xclip` answers those two invocations and synthesises the clipboard from
the filesystem, where Android screenshots actually land. `dot_local/bin/executable_clipshot` stages
an arbitrary image for the same path. Both are Android-only via `.chezmoiignore`.

| Behaviour | Why |
|-----------|-----|
| Serves the newest image in `~/storage/{pictures,dcim}/Screenshots` and `~/storage/downloads` | "Take a screenshot, then Ctrl+V" is the whole point; no app switch, no typing a path |
| Only if it is younger than `CLAUDE_CLIPBOARD_MAX_AGE` (default 600s) | Without a window, a Ctrl+V days later silently attaches a stale screenshot |
| Marks an image consumed once its bytes are read, so a second Ctrl+V reports empty | Makes it behave like a clipboard rather than a sticky file, and leaves Ctrl+V free to fall through to text. `CLAUDE_CLIPBOARD_REPEAT=1` opts out |
| Passes the file's raw bytes even when the target says `image/png` | Claude Code sniffs magic bytes after reading and derives the media type from them, so the JPEG that Android actually writes needs no conversion step |
| Text targets fall through to `termux-clipboard-get` | Gives Ctrl+V a working text path too, but only when the Termux:API package **and** app are installed |

`clipshot` covers what the age window deliberately excludes: `clipshot` alone stages the newest
image whatever its age, `clipshot <file>` stages a specific one, `-c` clears, `-s` shows what
Ctrl+V would attach.

**The watched folders are declared once**, in `dot_local/lib/claude-clipboard.sh`, which both
scripts source at runtime. They must agree by construction rather than by discipline: the shim
decides what Ctrl+V attaches and `clipshot -s` reports what the shim would pick, so a second copy
of the list would let the two answer differently on the same device, and `-s` would stop being a
diagnostic. Add a folder there, never in a consumer. The library returns the list through a global
rather than stdout for the same fork-budget reason as `_op_read_cache_names`.

`make test-clipboard-shim` drives the literal `xclip` command lines against a scratch
`CLAUDE_CLIPBOARD_DIRS`, covering both directions of the freshness window, the consumed marker
(including that `checkImage` must *not* consume, or the `saveImage` that always follows it would
attach nothing), and the agreement between `clipshot -s` and the shim.

**Do not "fix" this by installing an X server.** termux-x11 would give `xclip` a display, but that
display's selection is not Android's clipboard, so a screenshot still would not appear in it.

See `.docs/termux-clipboard-images.md` for how the contract was read out of the Claude Code
binary, the verification commands, and why termux-x11 and Termux:API were both rejected.

## Sentry CLI (npm, no wrapper)

`sentry` is the new Sentry CLI from [`getsentry/cli`](https://github.com/getsentry/cli), not the classic Rust `sentry-cli`. The Linux/WSL and Android installers both install it through the shared `install_sentry_cli` in `lib-install-deps.sh` with `npm install -g --ignore-scripts sentry`, and there is deliberately **no** Termux wrapper (Windows does not get it):

| Fact | Consequence |
|------|-------------|
| The official install script (`cli.sentry.dev/install`) downloads a Bun-compiled `sentry-linux-<arch>` executable linked against glibc; the `-musl` variants stopped shipping after `0.34.0` | On Termux the kernel cannot start it at all (`/lib/ld-linux-aarch64.so.1` does not exist under bionic), so the script dies with `No such file or directory` before `sentry cli setup` runs. Do not retry it there, and do not reach for `glibc-runner` or a musl loader: the npm route removes the need |
| The npm package `sentry` is the same CLI as a plain JavaScript bundle: no platform package, no lifecycle script, `engines.node >= 20` | It runs under Termux's native `nodejs` (bionic) and under NVM on Linux/WSL with one shared function body. Node 22.15+ uses the built-in `node:sqlite` for `cli.db`, kept in `$XDG_CONFIG_HOME/sentry/` (`~/.config/sentry/` by default; a legacy `~/.sentry/` that already holds one stays in use); older Node falls back to a bundled WASM driver |
| Node resolves DNS through bionic and reads Termux's CA bundle | No `termux-etc-seccomp`/`termux-etc-mount`, no `SSL_CERT_FILE`, no `LD_PRELOAD` parking. Verified on a device: `sentry cli upgrade --check` reaches the network and reports `Method: npm` |
| `sentry cli upgrade` detects the npm layout from its own path | Updates go through npm; nothing in the versions-directory style of the `claude` wrapper is needed |
| npm links `$PREFIX/bin/sentry` to the package's `dist/bin.cjs` and keeps its `#!/usr/bin/env node` shebang | The kernel resolves that path only through `termux-exec` in the calling process. Plain Termux tabs have it; Claude Code tool calls get it from the `claude-zsh` launcher (see the `LD_PRELOAD` contract above). Before that launcher every `sentry` call made directly from a tool call died with `bad interpreter: /usr/bin/env: no such file or directory` while `zsh -c 'sentry ...'` worked. Do not `termux-fix-shebang` the file as a workaround: `sentry cli upgrade` reinstalls it through npm and undoes that |

Log in with `sentry auth login`: the OAuth flow is a device code entered at a URL, so it works on the phone as-is, and `--token` accepts an API token instead.

**`sentry-ds` runs the CLI on the work (DarkSense) account.** `dot_zshrc.tmpl` defines it on both platforms, pointing `SENTRY_CONFIG_DIR` at `${XDG_CONFIG_HOME:-~/.config}/sentry-darksense`, a store of its own beside the default one, so neither login ever replaces the other. Log in once with `sentry-ds auth login`. The variable needs CLI 0.47.0 or newer, which the setup scripts below hold every machine at. Two details keep the accounts apart:

- **A token in the environment is dropped** (`SENTRY_AUTH_TOKEN`, `SENTRY_TOKEN`). The CLI prefers a stored login, but falls back to such a token whenever the store holds no valid one, so a fresh or logged-out work store would quietly run as whoever owns the token (verified: against an empty store, `sentry auth token` prints the exported one).
- **The path is built inside the function, never kept in a variable.** Claude Code's tool calls get `.zshrc`'s functions but not its variables, and an empty `SENTRY_CONFIG_DIR` selects the default store, so a variable would turn `sentry-ds` into the personal account in exactly those calls.

Its completion, `_sentry-ds`, runs Sentry's own `_sentry` with the same store: `_sentry` asks `sentry __complete` for org and project slugs, which would otherwise come from the personal account. `make test-zshrc-functions` covers all three.

**The setup scripts hold the CLI at the floor `sentry-ds` needs.** An older CLI ignores `SENTRY_CONFIG_DIR` without a word, so `sentry-ds` would run on the personal login and `sentry-ds auth login` would replace it, and the dependency installers install the CLI only where none exists, never upgrading it. Both setup scripts therefore include `.chezmoitemplates/lib-sentry-cli.sh` and, before anything else, raise a CLI older than its `SENTRY_CLI_MIN_VERSION` (`0.47.0`), or one that reports no version, with `sentry cli upgrade`:

- **`sentry cli upgrade`, not `npm install`.** It upgrades through whichever method installed the CLI. A standalone binary from the curl installer (`~/.local/bin/sentry`) sits ahead of npm's on PATH, so an npm upgrade would leave the CLI that actually runs where it was; the version is checked again afterwards for the same reason. Its own setup step passes `--no-modify-path`, so an upgrade never edits the managed `~/.zshrc`.
- **A CLI that stays older fails the script**, unlike a failed `cli setup`, so chezmoi runs it again on the next apply instead of recording it as done. A machine with no CLI at all only gets a warning: `sentry-ds` then fails outright, on no account.
- **Raising the floor is one edit.** It changes both rendered scripts, and that re-runs them on every machine. Do not move the check into `install_sentry_cli`: `lib-install-deps.sh` is rendered into both `run_once_` installers, so any edit there re-runs the whole 45-120 minute install on every machine.

`make test-sentry-setup` covers the comparison, the upgrade and both failures on both platforms, plus the Linux script finding the CLI under NVM.

npm installs ship neither shell completions nor the agent skill, so `run_onchange_after_linux-007-setup-sentry-cli.sh.tmpl` and `run_onchange_after_android-006-setup-sentry-cli.sh.tmpl` run `sentry cli setup --no-modify-path` after the managed files are applied, with `SHELL` pinned to zsh (the CLI installs completions for the shell `SHELL` names, and the first Linux apply runs under bash). Three things about that command are easy to get wrong:

- **`--no-modify-path` only skips the PATH edit.** The zsh completion step still appends `fpath=("<dir>" $fpath)` to `~/.zshrc` unless the file already contains the completion directory as a quoted absolute path. `dot_zshrc.tmpl` therefore renders `"{{ .chezmoi.homeDir }}/.local/share/zsh/site-functions"` into its own `fpath` line before Oh My Zsh runs compinit. A `$HOME`-based line would not satisfy the check, and the CLI's appended line is exactly what the next apply reverts (observed on a device: a manual run appended it, and `chezmoi diff` wanted it gone).
- **The setup runs after the files on purpose.** From `run_once_before` it would edit the previous `~/.zshrc` first, and the file application that follows would stop to ask about an externally modified target.
- **The agent skill lands in `~/.claude/skills/sentry-cli/` only when `~/.claude` exists**: always on Android, where chezmoi manages it; on Linux after Claude Code's first run, added by the next `sentry cli upgrade`, which re-runs the same setup after every upgrade (that is why the scripts are `run_onchange_` and not `run_after_`). aisync leaves the skill alone: its deletion detection covers only files it synced itself, and it prompts before removing anything.

## Neon CLI (npm, no wrapper)

`neon` is the Neon CLI from [`neondatabase/neon-pkgs`](https://github.com/neondatabase/neon-pkgs), for Neon Serverless Postgres. The Linux/WSL and Android installers both install it through the shared `install_neon_cli` in `lib-install-deps.sh` with `npm install -g --ignore-scripts neon`, and there is deliberately **no** Termux wrapper (Windows does not get it, as with the CLIs above):

| Fact | Consequence |
|------|-------------|
| Fresh installs take the `neon` package, never `neonctl`: since the two-package split, `neon` holds the CLI and the `neon` executable, while `neonctl` is a compatibility shim whose only executable imports `neon/cli` in-process | One package to install; a machine that installs `neonctl` for the legacy command name is running the same CLI, so the repository never carries both. Since the rename, `neon --version` is what reports the CLI's version |
| The package is the whole CLI as a plain JavaScript ESM bundle (`bin` links `neon` to `dist/cli.js`, `#!/usr/bin/env node`), `engines.node >= 20.19.0` | It runs under Termux's native Node and under NVM on Linux/WSL with one function body. npm treats a mismatched engine as a warning, so `install_neon_cli` skips with a warning below 20.19.0 instead of installing a launcher the CLI's docs say cannot run or upgrade. The shebang needs termux-exec in the calling process — the Sentry CLI's story, with plain Termux tabs and the tool-call shells covered by `claude-zsh` |
| `@napi-rs/keyring`, the opt-in `--keyring` OS-keyring storage, publishes no android-arm64 target, and the CLI's `tryLoadKeyring` returns null when the addon cannot load | On the phone, credentials stay in the CLI's config file — which is the default anyway — and `--keyring` reports that the OS keyring is unavailable instead of crashing. Nothing here needs a wrapper |
| `esbuild` is an optional dependency serving only the bundling commands, resolved lazily at call time, with the platform binary arriving through `@esbuild/<platform>` packages | `--ignore-scripts` skips only esbuild's fallback postinstall, which exists for installers that disable optional dependencies; verified with that postinstall skipped, the JS API still bundles. If the import ever fails, the CLI names `NEON_ESBUILD_PATH` |

Log in with `neon login` (a browser flow; on WSL the `open` package launches Windows' default browser), or authenticate with an API key: `NEON_API_KEY` in the environment, `--api-key`, or `neon profile create <name> --api-key -`, which reads the key from stdin so it never reaches an argument list. On the phone the API key route is the one to rely on, and a `cred:NEON_API_KEY` field on the device note reaches every shell through the existing credential loader.

Verified on Linux (the `--ignore-scripts` install, `neon --version`, and esbuild with its postinstall skipped); the Termux half rests on the same properties as the Sentry CLI's and is not yet verified on a device.

## AI Rules Sync

AI assistant rules (Claude Code, OpenCode, etc.) are **not** managed by chezmoi. Everything the harnesses load as AI content lives in their own directories and is synced separately by [`aisync`](https://github.com/rios0rios0/aisync), a Go CLI installed by `install_aisync()` in the Linux/WSL and Android dependency scripts (replaces the legacy `run_after_*-install-ai-rules.*` scripts that used to curl `install-rules.sh` from `rios0rios0/guide` on every apply): `~/.claude/CLAUDE.md` and `~/.config/opencode/AGENTS.md` carry the per-machine environment reality (WSL facts, the interactive `cp`/`rm`/`mv` guards, quoting rules), and `rules/`, `agents/`, `commands/` and `skills/` under each directory carry the portable content. chezmoi touches only the individual files there that "JSON Patching" and "Claude Code Look" name, plus OpenCode's `opencode.json` and `cli.json`.

After the dependency installer finishes, run `aisync init`, `aisync source add guide --source-repo rios0rios0/guide --branch generated`, and `aisync pull` to populate the rules. Subsequent `aisync pull` calls refresh them on demand.

## Claude Code Look

Claude Code's look is declared here and merged into its settings file by a modify-template, which
sets a managed key whose value differs and leaves every other key alone:

| Look | Declared in | Merged into |
|------|-------------|-------------|
| Claude Code: `theme` `dark-ansi`, `tui` `fullscreen`, `statusLine` | `.chezmoitemplates/lib-claude-look.tmpl` | `~/.claude/settings.json`, Linux only |
| Claude Code's status line | `dot_claude/executable_statusline-command.sh` | `~/.claude/statusline-command.sh`, Linux only |

**Change the look here, never with `/theme` or `/statusline`.** Those write the same keys, so
the next apply sets them back, with a `[claude-settings]` line naming each one.

1. **The status line follows `CLAUDE_CONFIG_DIR`.** It finds its credentials, usage cache and
   account through it, so a profile without a claude.ai login shows no plan limits. Without a
   login it also starts no usage refresh: one that cannot succeed never writes the cache, and
   would fork on every redraw.
2. **The OAuth token never reaches an argument list.** The refresh hands it to `curl` on
   stdin (`-H @-`), because any local user can read a process's arguments in
   `/proc/<pid>/cmdline`.
3. **Claude Code's look stays on Linux.** The status line forks bash and jq on every redraw,
   which on Termux counts against Android's phantom-process budget. `.chezmoiignore` therefore
   ships only `settings.json` and the script from `dot_claude/` to Linux and keeps the script off
   Android; Windows, where Claude Code is no longer installed, gets neither `~/.claude` nor
   `~/.claude.json`. `dot_claude/modify_settings.json` branches on the platform: the look on
   Linux, the permission rules and `effortLevel` on Android as before -- Linux never had them.

`make test-modify-scripts` covers every merge and the byte-for-byte passthroughs;
`make test-chezmoiignore` covers which platform gets which file; `make test-statusline`
covers the script with and without a login, including 1 and 2, against stubbed `curl` and
`mkdir`.

## Non-Interactive Shell Guards

These ship to every platform, not only Android: both blocks sit outside the chezmoi platform conditionals, because the behaviour they guard against comes from Claude Code's Bash tool, which snapshots the interactive shell's aliases and functions into its non-interactive runs on Linux/WSL exactly as on Termux.

- `dot_zshenv.tmpl` relaxes `nomatch` for non-interactive shells (`[[ -o interactive ]] || setopt NO_NOMATCH`), so a glob that matches nothing is passed through to the command instead of aborting the whole line. Interactive shells keep the prompt-time error.
- `dot_zshrc.tmpl` replaces the `common-aliases` `rm`/`cp`/`mv -i` aliases with functions, defined right after oh-my-zsh loads, that keep `-i` only when stdin is a terminal. Against a closed stdin `-i` reads EOF and skips the operation with exit 0 — a `cp` that never happened, reported as success.

## Claude Account Rotation (ccswitch)

Claude Code subscription tokens live in `~/.claude/.credentials.json` (not chezmoi-managed on Linux/WSL). [`ccswitch`](https://github.com/rios0rios0/ccswitch) is a Go CLI installed by `install_ccswitch()` in the Linux/WSL dependency script that monitors Claude Code usage (via the `GET /api/oauth/usage` OAuth endpoint) and rotates between enrolled backup accounts when the active account's limits are exhausted.

`dot_zshrc.tmpl` (Linux only) starts the `ccswitch monitor` daemon in interactive shells and wraps `claude` so each launch first runs `ccswitch ensure` — a no-network guard that installs the current account's credentials. Enroll each account once with `ccswitch enroll` after logging in via `claude` + `/login`; afterwards rotation is automatic, with no repeated `/login`. The `[ccswitch]` log prefix is emitted by the tool itself.

Both entrypoints run the same `_claude_ensure_account` guard before launching, so rotation applies whichever one is used: `claude` (plain) and `claudex` (`--dangerously-skip-permissions --effort max`). The guard is a no-op when `ccswitch` is absent, keeping both usable on platforms that never install it.

Keep `claudex` a **function**, not an alias: zsh refuses to define a function whose name is already an alias, and aliases are expanded only in interactive shells, so an aliased `claudex` does not exist in scripts, `zsh -c`, or `sudo zsh -c`. Keep its guard call **explicit** too — relying on a bare `claude` to pick up the wrapper works only because a bare command word resolves to a function before a binary, so changing it to `command claude` would silently drop rotation.

**Note:** if `ANTHROPIC_API_KEY` or `ANTHROPIC_AUTH_TOKEN` is set, Claude Code ignores the rotated OAuth credentials; `ccswitch` warns when it detects this.

## Local Model Server (Ollama)

Ollama serves `.chezmoidata/local-llm.yaml`'s model from each Linux machine's NVIDIA GPU. It is one of OmniRoute's providers. Setup, measurements and troubleshooting are in `.docs/local-coding-model.md`; these are the invariants:

| Part | Where |
|------|-------|
| Settings (model, window, cache, keep-alive, tailnet share, per-device overrides) | `.chezmoidata/local-llm.yaml`, read through `.chezmoitemplates/lib-local-llm.tmpl` |
| Install, restart on change, model pull, GPU-discovery check | `.chezmoiscripts/run_onchange_after_linux-009-setup-ollama.sh.tmpl` |
| Server | `dot_config/systemd/user/ollama.service.tmpl` (a user unit) |
| Share on the tailnet, for another machine's OmniRoute | `dot_local/bin/executable_tailscale-up.tmpl` |
| Gate | `.chezmoiignore`: Linux **and** `nvidia-smi` on `PATH`, not WSL |

**Keep these, each prevents a failure that was observed or measured:**

1. **One window, from one value.** `contextTokens` becomes `OLLAMA_CONTEXT_LENGTH`, what the server allocates. OmniRoute cannot read it from Ollama and advertises its 128000 fallback instead. Never hard-code the window anywhere else.
2. **The marker is a commit record.** The installer writes the release marker only after `sync`, and re-verifies every unpacked file against a digest manifest each time it runs. A WSL VM that went down after an install once left both `libcublasLt` libraries truncated under a valid marker; CUDA discovery then died with `SIGBUS` on every start, and Ollama served from the CPU without a visible error.
3. **The installer proves GPU *discovery*, and loads nothing.** It reads the server's own start-up log, filtered to the invocation it just restarted -- one `inference compute` line per backend, `library=cpu` alone meaning no accelerator answered -- and fails the apply when no other backend is there. Loading the model to inspect where Ollama placed it, which this used to do, put ~17 GB of weights in VRAM at every apply and paid a ~17 s cold start that the first real request would otherwise have re-used; the model now stays out of VRAM until something asks for it, and `keepAlive` gives the VRAM back afterwards. The failure it catches is unchanged: a damaged CUDA install (a WSL VM once went down mid-install, leaving the two `libcublasLt` libraries truncated) makes discovery crash, `cpu` becomes the only backend, and Ollama then serves every request from the CPU -- an order of magnitude slower -- with no error. What used to be an observed partial placement is now a forecast: the free VRAM the log's GPU line reports, against the model's size, warns when even the weights cannot fit.
4. **Gate on the driver and the OS, not on WSL.** Nothing here depends on Windows, so bare-metal Linux with a GPU qualifies; but `lookPath` finds `nvidia-smi.exe` on Windows too, so `.chezmoiignore` pairs the driver check with `eq .chezmoi.os "linux"`.
5. **Device overrides are laid over key by key.** sprig's `merge` and `mergeOverwrite` both count `false` as empty, so a device's `enabled: false` would lose to the default `true`; `lib-local-llm.tmpl` uses `set` per key instead.
6. **Ollama binds IPv4 loopback, and the specific address is load-bearing on WSL.** The family of the listening socket decides the family WSL's localhost forwarding publishes on the Windows side: a dual-stack `0.0.0.0` bind appears there on `::1` alone, and Docker Desktop -- which reaches this machine as `host.docker.internal`, dialing Windows' IPv4 loopback -- gets connection refused, surfacing as a 502 on every local GPU request through OmniRoute. `127.0.0.1` publishes Windows' `127.0.0.1`, so the container connects. Tailscale needs no change either way: Windows' client forwards to `localhost:11434`, which names both families. The API has no authentication, so on WSL every Windows-side process can run inference and pull or delete models; keep the tailnet share to devices you trust.

`make test-local-llm` covers 1, 3, 5, the installer's render gate and a stubbed end-to-end run of it (nothing loaded, the invocation filter, the busy-GPU warning, and both failure logs); `make test-chezmoiignore` covers the gate per platform. Ollama and its models live under `$HOME`, so removing the server means `path:` tombstones for `.local/share/ollama` and `.ollama`, disabling the user unit, and `.chezmoiremove` entries for `~/.config/systemd/user/ollama.service` and `~/.local/bin/ollama`.

## The OmniRoute Fork Image

The Compose stack in `local-services/omniroute/` runs `ghcr.io/rios0rios0/omniroute`, a build
of the `reworked` branch of the `rios0rios0/OmniRoute` fork, not the official
`diegosouzapw/omniroute` image: the gateway needs that branch's model-scoped quota endpoint.
The fork's own `.github/workflows/publish-ghcr.yml` publishes it on every push to the branch.
`local-services` is in `.chezmoiignore`, so none of this is deployed by `chezmoi apply` -- the
stack is run from the checkout, and the digest in `compose.yaml` is what decides what runs.

| Part | Where |
|------|-------|
| Image | `ghcr.io/rios0rios0/omniroute`, digest-pinned in `local-services/omniroute/compose.yaml` |
| Build | the fork's `publish-ghcr.yml`, `runner-base` for `linux/amd64`, on every push to `reworked` |
| Pin update | `local-services/omniroute/update-image.sh` (requires `gh` and `docker` buildx) |
| Guide | `.docs/omniroute-local.md`, "The custom fork image" |

**Keep these, each prevents a failure that was observed or measured:**

1. **The pin is a digest, never the branch tag.** Every build publishes `:reworked` (moves
   on each push) and `:sha-<full commit>` (immutable). `update-image.sh` asks GitHub for the newest
   successful run, resolves that commit's tag and rewrites only the `omniroute` image line. Pinning
   the branch tag would let `docker compose pull` change what runs with no commit to name it. The
   helper reads a pin back with the same matcher it writes with -- repository name, either quoting
   style -- so a mirror named by `OMNIROUTE_IMAGE` and a pin an earlier run wrote both stay
   updatable; the rewrite is verified against that matcher before it replaces the file.
2. **CI builds it, not the checkout.** The image is a Next.js build with a 12 GB heap, 27-55 minutes
   on a hosted runner (`target: runner-base`, `OMNIROUTE_USE_TURBOPACK=0`,
   `OMNIROUTE_BUILD_MEMORY_MB=12288`, `linux/amd64` -- the settings upstream's publish workflow
   validated). The fork checkout is sparse, so `docker build .` from it fails until
   `git sparse-checkout disable`, and rebuilding on every apply would cost an hour -- the `ocode`
   pattern covers a binary built in seconds, not an image.
3. **The Compose project and volume names are load-bearing.** `name: 'dotfiles'` and the
   `volumes:` block keep `dotfiles_omniroute-data` and `dotfiles_omniroute-redis-data`, so swapping
   the image reuses the database, provider credentials and Redis state; a renamed project makes
   Compose create empty volumes instead. That is also why `local-services/omniroute/` does not move.
4. **`runner-base` means no web-cookie providers.** `gemini-web`, `claude-web` and
   `claude-turnstile` need the `runner-web` target's Chromium; that target is one line in the fork's
   workflow. Everything this stack uses (Ollama, NVIDIA NIM, OpenRouter) is in base.
5. **Migrations are one-way, so a backup comes first.** The fork is based on upstream `v3.8.52`, and
   its first start migrates the v3.8.51 database. `omniroute-backup` takes a `VACUUM INTO` snapshot
   encrypted with the backup key; rolling the image reference back restores neither the schema nor
   the data, so the archive is the rollback.
6. **The package is public; a private one needs a login.** The fork is public, so GHCR serves the
   image anonymously. If its visibility changes, `docker login ghcr.io` with `read:packages` must
   run before `docker compose pull`, or the pull fails while the previous image keeps running.

`make test-omniroute-image` covers 1 and the failures -- the first switch away from the official
image, `--check` in both directions, `--tag`, a file with no recognised digest, and every failed
lookup leaving the pin untouched -- against stubbed `gh` and `docker`.

## OpenCode V2 Through OmniRoute

OpenCode runs on the OmniRoute gateway: `dot_config/opencode/opencode.json.tmpl` renders to `~/.config/opencode/opencode.json`, with OmniRoute as the primary provider and `omniroute/auto/coding` as the default model. It discovers the catalog from the gateway's own `/v1/models`, which serves exactly what the API key allows, so no model list is carried here. The CLI that reads it on Linux is `ocode`, the fork build below; the official `opencode` binary is no longer installed. Setup and usage are in `.docs/opencode-local.md`.

| Part | Where |
|------|-------|
| Global config | `dot_config/opencode/opencode.json.tmpl`, applied on every platform that gets a shell |
| CLI | `ocode`, built into `~/.local/bin/ocode` by `run_after_linux-006-build-ocode.sh` (see "The Fork Build" below), Linux only |
| Look | `dot_config/opencode/cli.json` |
| Rules | `~/.config/opencode/AGENTS.md` and `rules/`, synced by aisync, not chezmoi; each project's `CLAUDE.md` arrives through `instructions` |
| Key | the `cred:OMNIROUTE_API_KEY` field of the device note, exported by the credential loader and read at config load as `{env:OMNIROUTE_API_KEY}` |

**Keep these, each prevents a failure that was observed or measured:**

1. **`{env:VAR}` is load-time substitution; a `${VAR}` key is a silent 401.** OpenCode expands `{env:...}` and `{file:...}` anywhere in the document when it loads it, and `${...}` only inside a provider's `settings.baseURL`. Measured against the live gateway: with `${OMNIROUTE_API_KEY}` as the apiKey, discovery returns no models at all; with `{env:OMNIROUTE_API_KEY}`, the key's whole catalog.
2. **The model list is discovered, and the key policy is the source of truth.** `/v1/models` serves the ids the key's rules allow, so the repository holds no list to drift; allow a model in OmniRoute's dashboard, never here. The plugin drops `type: "image"` rows, keeps `context_length` as the window and `capabilities.tool_calling` as tool support; measured: 158 chat models of the key's 162 rows.
3. **The MCP field is `environment`.** V2 reads `environment` on a local MCP server; an `env` key is ignored with no diagnostic, and the variable silently never reaches the server. `make test-opencode` asserts `environment` and the absence of `env` on every server.
4. **The `dotfiles` reference is absolute on purpose.** A local reference path resolves against the config document's directory unless absolute; the template renders `{{ .chezmoi.sourceDir }}`, so a session reads the actual dotfiles checkout (usually `~/.local/share/chezmoi`).
5. **Permissions are V2 ordered entries** (`{action, resource, effect}`), the same allowances as the Claude Code side; what the list does not allow, the TUI still asks for.

`make test-opencode` covers all of it without OpenCode or a gateway running: it renders the template on both platforms, parses the JSONC, and checks the provider, defaults, MCP server shape, reference, instructions and permissions. Removing the feature means `.chezmoiremove` entries for `~/.config/opencode/opencode.json` and `cli.json` -- not for the directory itself, where OpenCode keeps files of its own, including the aisync-synced rules, agents, commands and skills.

### The Fork Build (`ocode`)

`ocode` is the personal fork's build of OpenCode, carrying the custom features the official binary
lacks: the OmniRoute provider plugin and the `OPENCODE_DISABLE_CLAUDE_CODE` gate, both on branch
`reworked` of `rios0rios0/opencode`. `run_after_linux-006-build-ocode.sh` keeps it
current, checkout included: a missing one at `~/Development/github.com/rios0rios0/opencode` is cloned
from the fork straight onto that branch (with the fork named `fork` and sst upstream named
`origin`, as the hand-made checkouts on these machines have them), and an existing one sitting on
another branch is switched to it. The branch is not optional bookkeeping -- the build stamps the
channel onto whatever HEAD holds, so a checkout left on `main` would produce a binary labelled as
the fork and carrying none of its code. It then runs the fork's own single-platform build whenever
the checkout's HEAD moved past the last one, and
installs the result as `~/.local/bin/ocode`. The build pins the channel and version the Console
reads from the User-Agent -- `OPENCODE_CHANNEL=feat-provider-omniroute` and a build-stamped
`OPENCODE_VERSION` (`<release>-reworked.<%y%m%d%H%M>`, e.g. `2.1.4-reworked.2610241230`, with
`<release>` the checkout's `packages/cli/package.json` `version`, or 2.0.0 with a warning when that
names no release) -- because the free tier refuses client versions below 1.18.0, which a bare
branch build's `0.0.0-<branch>-<time>` preview version is; the stamp also makes each rebuild
replace the background service on the next launch. The marker
`~/.cache/ocode-built-commit` makes an unchanged apply a no-op, which is why this is a `run_after`
script that runs on every apply; `OCODE_SOURCE` names another checkout. No `bun`, a failed clone,
a directory at the checkout's path that is not a checkout, and a checkout holding neither the
branch nor the fork's remote-tracking one are skips, never failures -- the last two because an
apply with no network must still finish, and the third because that directory may hold somebody's
work. A failed build -- a failed dependency install included -- is an error, retried by the next
apply.

A running `ocode` -- the TUI or the server it spawns -- executes `~/.local/bin/ocode`, the file
the build replaces. The builder looks for the processes executing **that file** (through
`/proc/<pid>/exe`, not by name: an `ocode` started from another path holds no file of ours) and,
when it finds any, asks whether to kill them, because they are somebody's session and killing one
ends it. The answer never decides whether the build happens, though: the install stages the new
binary under a temporary name beside the target and renames it into place, and a rename replaces
the directory entry while the running process keeps the old inode. An answer of no -- and an
unattended run, where stdin answers nothing -- therefore leaves the session alone and builds
anyway, and the session keeps the binary it started with until it restarts; yes kills first, and
a process that survives SIGKILL is only warned about, never a reason to skip. An `ocode` started
*while* the build runs is safe for the same reason.

bun, the build's runtime, comes from `install_bun` (shared library, called by the Linux
installer) as `~/.bun/bin/bun`. The upstream `bun.sh/install` script would append its own PATH
line to the rc file of whichever shell `$SHELL` names -- `~/.zshrc`, which chezmoi owns and
rewrites -- so `install_bun` runs it with `SHELL` empty, which falls through to printing the
manual instruction, and `dot_zshenv.tmpl` carries the `~/.bun/bin` PATH block. The builder
resolves bun from PATH and falls back to `~/.bun/bin/bun`, so the first apply after the install
builds even though the running shell's PATH predates the export; only when neither answers is
the build skipped.

That bun is the machine's, though, and the checkout pins its own: the `packageManager` field of
its root `package.json` (`bun@X.Y.Z`), which upstream OpenCode's CI
(`.github/actions/setup-bun`) reads to install exactly that version. The two drift apart -- a
`bun upgrade`, a rebase that moves the pin -- and a newer bun is no drop-in: bun 1.4.4 refused a
patch file in the checkout (`hunk #10 does not apply to photon_rs.js`) that its 1.4.2 pin
applies. So on every build the builder runs `bun install --frozen-lockfile` in the checkout and
then the build, both with the pinned bun and with that bun's directory first on PATH, because
the root `postinstall` and the build spawn `bun` themselves. The pinned bun is the resolved one
when it is that version, and otherwise a copy under `~/.cache/ocode-bun/<version>/`, which the
first build that needs it downloads from bun's GitHub release, not through `bun.sh/install`,
which would replace `~/.bun`. The asset is the one `bun.sh/install` would pick:
`bun-linux-x64.zip`, its `-baseline` build on a CPU without AVX2, or `bun-linux-aarch64.zip`. The
zip is verified against the release's `SHASUMS256.txt` before anything is extracted, and the
binary is cached only once it reports the pinned version, so a build this CPU cannot start
never lands there. A missing or non-release pin (a range, `canary`, another package manager), an
unreadable `package.json`, an architecture bun publishes no build for and a failed download
all warn and fall back to the resolved bun, so an apply without the network still finishes.
Versions the checkout no longer pins stay in the cache until it is cleared (each is a whole bun
binary: 1.4.2 is 80 MB, 1.4.4 107 MB).

The install runs because the build takes it for granted: the fork's `--skip-install` skips only
the build's own cross-platform install of the native `@opentui/core` and `@opencode-ai/pty`
packages, and a fresh clone, which nothing had installed, failed with dozens of
`Could not resolve: "effect"`. `--frozen-lockfile` installs exactly `bun.lock`, as upstream's CI
does, and fails rather than rewrite the lockfile of somebody's checkout. Lifecycle scripts stay
on: the root `postinstall` restores the execute bit on node-pty's prebuilt `spawn-helper`. An
unchanged apply still runs neither.

`make test-ocode` covers the checkout the builder obtains itself (the clone onto the fork's
branch and the remote layout it leaves, the branch switch, the branch created from the fork's
remote-tracking one, a checkout holding no fork branch, a directory that is not a checkout, and a
failed clone that only warns), the skip without bun, the first build (including the channel and
release-grade version it carries, and the dependency install that precedes it), the no-op and
the rebuilds against stubbed `git` and `bun`, the running-`ocode` prompt with no answer, a
decline and an acceptance, the process started mid-build, the pinned bun against a stubbed
release (the resolved bun at the pin, a cached copy, a stale cached copy fetched again, the x64
and arm64 downloads, HTTPS-only, each then running the install and the build from the front of
PATH), every fallback (no network, a checksum mismatch, a binary that cannot start, an
unsupported architecture, a missing, non-release or unreadable pin), the failed install that
fails the apply, and the installer's skip, its `SHELL`-empty call, both failures, the Linux
wiring and the PATH block per platform.

`chezmoi apply` is not the only way to run the build: the `rebuild-ocode` zsh function (Linux
only) resolves the same script through `chezmoi source-path` and runs it, so a build can be
caught up after pulling the checkout, or when an apply found nothing to build, without a whole
apply. `make test-zshrc-functions` covers it.

## Tailscale

Every Linux machine joins the tailnet, through one client per machine: on WSL that client is
Windows', on bare metal `tailscaled`. `dot_local/bin/executable_tailscale-up.tmpl` and the
installer render one way or the other from the kernel, as `.chezmoiignore` does.

| Part | WSL | Bare metal |
|------|-----|------------|
| Client | Windows', `Tailscale.Tailscale` in `run_once_before_windows-001-install-dependencies.ps1` | `tailscaled`, from Tailscale's apt repository |
| `tailscale` in a shell | `dot_local/bin/executable_tailscale`, a wrapper for `tailscale.exe` | the package's |
| Login | the Tailscale app on Windows | `tailscale-up`, which waits for the browser |
| Sharing the model's server | `tailscale-up`, through Windows' `tailscale serve` | `tailscale-up`, through `tailscale serve` |
| `.chezmoiscripts/run_onchange_after_linux-010-setup-tailscale.sh.tmpl` | runs `tailscale-up --no-login`, nothing else | installs, enables `tailscaled`, logs in |
| Shell hook (`dot_zshrc.tmpl`, "Tailscale") | none | `tailscale-up --no-login` in every interactive zsh |

**Keep these:**

1. **On WSL the client is Windows', and nothing runs one inside WSL.** Tailscale's WSL guide says
   that with clients in both, WSL's traffic through the Windows one fails, because of "Tailscale
   packets not being able to fit in Tailscale packets". Windows' client also reaches what one in
   WSL cannot: Windows' own services, and Docker Desktop's containers, whose traffic leaves
   through Windows -- with the client in WSL, a container timed out on this machine's own tailnet
   address, because Windows had no route into the tailnet. The Linux removal script drops the
   Linux client from WSL machines that had it (an `apt` tombstone, which needs passwordless sudo),
   and `tailscale-up` warns while a `tailscaled` still runs there.
2. **Nothing on WSL waits for a login, needs root or runs per shell.** Windows' client is a service
   that starts with Windows and rejoins by itself, and its app owns the login. Asking it from
   every shell would launch a Windows process each time (130-330 ms measured), so WSL has no
   hook: the apply runs `tailscale-up --no-login`, which shares the model's server once Windows is
   on the tailnet and otherwise only hints. It leaves a client switched off in the app as it is;
   `tailscale-up` asked directly switches it back on with a bare `tailscale up`.
3. **WSL's share is Windows' `tailscale serve`, to `localhost:11434`.** The family of the relay's
   Windows listener follows the family of the WSL socket: Ollama binds IPv4 loopback, so the relay
   appears on Windows' `127.0.0.1`, and a dual-stack bind would put it on `::1` alone. `localhost`
   reaches whichever it is, so the share survives such a change unedited; WSL's own address would
   answer too, but it changes whenever WSL starts. A share left on the other literal is moved by the
   next apply (9). The wrapper's path is fixed, as `op-ssh-sign-wsl`'s is in `dot_gitconfig.tmpl`;
   `TAILSCALE_EXE` names another.
4. **Bare metal: the shell's pass never waits and never asks for a password.** It runs in every
   interactive zsh, so a logged-out machine gets a one-line hint pointing at `tailscale-up`, not a
   login that blocks the prompt, and a failed daemon gets a hint, not `sudo systemctl`. A daemon
   that is enabled and not failed is still starting, and gets nothing at all.
5. **Bare metal: the operator is set once, through sudo, at the first login.** `--operator=$USER`
   is what lets the shell's pass bring a node back up, and `tailscale serve` run, without root.
6. **Bare metal: the shell's pass uses a bare `tailscale up`.** Only the bare form is the "just
   switch it back on" special case; any flag, even `--timeout`, makes `tailscale up` re-check every
   non-default preference and fail with `requires mentioning all non-default flags`. The direct
   call spells out both preferences for the same reason, and `tailscale set` re-applies them to a
   node logged in some other way without touching the rest.
7. **Bare metal: MagicDNS stays off (`--accept-dns=false`).** Without a DNS manager, tailscaled
   replaces `/etc/resolv.conf`, and every lookup fails while it is down. Peers are reached by
   address: `tailscale ip -4 <name>`, or `tailscale status --json`. WSL can leave MagicDNS on:
   it resolves through Windows (DNS tunneling, `nameserver 10.255.255.254`), whose client
   answers tailnet names without touching `/etc/resolv.conf`.
8. **Bare metal: the repository key is checked before apt trusts it:** exactly one key, with
   Tailscale's fingerprint. A keyring carrying a second key would make apt trust that one too.
   Upstream's `install.sh` maps every Kali release since 2021 to the Debian bullseye suite; the
   package is the same static build for every release.
9. **The installer tracks `tailscale-up`'s rendered digest**, so switching `shareOnTailnet` or the
   local model on or off re-runs it, and the share follows.
10. **A WSL machine serves only while its WSL runs.** Windows stops WSL a few seconds after the
    last WSL terminal closes, and the Ollama unit with it; Windows' share then forwards to a port
    nothing listens on. Nothing here keeps WSL running, by choice: whoever wants the desktop's GPU
    opens a terminal there (RustDesk) and leaves it open. Windows' client keeps the machine on the
    tailnet meanwhile, and `tailscale set --unattended=true` keeps it there after its user signs
    out and before the first sign-in after a reboot.

What the Linux client leaves behind on WSL is root's, so no tombstone reaches it:
`sudo apt-get purge -y tailscale` also removes `/var/lib/tailscale`, and
`sudo rm -f /etc/apt/sources.list.d/tailscale.list /usr/share/keyrings/tailscale-archive-keyring.gpg`
drops the repository. Delete that machine in the admin console too, so that Windows' node can
take its name.

`make test-tailscale` covers 1 to 6 and 9 against stubs of both clients, `systemctl` and `sudo`,
and the removal on WSL alone; `make test-chezmoiignore` covers the gates.

## systemd on WSL (Turned On by chezmoi)

The SSH agent bridge, Ollama and the OmniRoute backups run as systemd user units, and WSL boots a
distribution with systemd only when `/etc/wsl.conf` has `systemd=true` under `[boot]`. Kali's WSL image ships no
`/etc/wsl.conf`, so PID 1 is WSL's own `init`. `systemctl --user` then fails with `Failed to connect
to user scope bus via local transport: No such file or directory` -- the socket it looks for in
`$XDG_RUNTIME_DIR`, WSLg's `/mnt/wslg/runtime-dir`, does not exist -- and none of those units can
start.

Two halves make the fix automatic, and both are needed:

| Half | Mechanism |
|------|-----------|
| Turn it on | `.chezmoiscripts/run_before_linux-000-enable-wsl-systemd.sh.tmpl` sets `systemd=true` under `[boot]` through sudo and says to restart WSL. It renders to nothing unless the kernel is WSL's and systemd is not PID 1, so it runs on every apply until WSL boots with systemd, and never after |
| Finish what waited | Each installer that calls `systemctl` -- the bridge, Ollama, the OmniRoute backups, and Tailscale's bare-metal half -- renders `systemd running` or `systemd not running` into a comment. Without systemd it stopped early and exited 0, which chezmoi records as done; the line changing is what runs it again on the first apply after the restart |

On a machine that boots without systemd: `chezmoi apply` writes the file and the installers warn;
`wsl.exe --shutdown` and a new terminal start systemd; the next `chezmoi apply` sets up the bridge
and Ollama, pulling the model. Tailscale does not wait: on WSL its client is Windows' (see
"Tailscale").

**Keep these:**

1. **Every `run_once_` or `run_onchange_` script that calls `systemctl` carries the systemd line**,
   rendered from `stat "/run/systemd/system"`, the same test the script makes at run time. That
   directory exists exactly when systemd is PID 1; it is what `sd_booted()` checks.
2. **Wait for systemd with exit 0 only when it is not PID 1**, the one state the line records.
   With systemd running, a user manager the session cannot reach changes no line, so it is an
   error: only a non-zero exit makes chezmoi retry the script instead of recording it as done.
3. **The restart is the user's.** `wsl.exe --shutdown` ends every WSL process, the apply that would
   call it among them. The script tells a restart still due from one that did not take by comparing
   the file's mtime with PID 1's start, and points a WSL older than 0.67.6, which ignores the
   setting, at `wsl.exe --update`.
4. **The file is merged, never replaced.** Every other line of `/etc/wsl.conf` stays. A file that
   already asks for systemd is not rewritten, and a changed one is renamed over the old from a
   sibling, because WSL reads it at every boot.
5. **Expected failures are warnings.** A refused sudo or a distribution without systemd installed
   exits 0: this runs before every installer, where a non-zero exit would stop the whole apply.

`make test-wsl-systemd` covers the render gate, the merge, both restart messages, and the systemd
line in every installer that calls `systemctl`, which also catches a new one that lacks it.

## Claude Code Voice Input (WSL)

Voice input (push-to-talk on the spacebar) shells out to a recorder binary, probing three options in order:

1. `arecord` (ALSA) — probed first, but WSL exposes no `/dev/snd`, so this path can never succeed here
2. `sox` **and** `rec` — the working path on WSL
3. neither → voice input is reported unavailable and pauses after repeated failures

WSLg already provides the server half: it exports `PULSE_SERVER=unix:/mnt/wslg/PulseServer` and exposes a
`PulseAudioRDPSource` for the microphone. Only the client half is missing, which is why `sox` **and**
`libsox-fmt-pulse` both sit in the `utilities` array of the Linux dependency installer — plain `sox` cannot
reach the WSLg socket without the PulseAudio format handler, and the `sox` package is what provides `rec`.

The failure message ends with "If WSLg is not available (for example WSL1), run Claude Code in native Windows
instead." **That is not a diagnosis** — it is the tail of case 3 and prints whether or not WSLg is present.
Check for `sox` before concluding anything about WSLg.

`run_once_` keys its state on the SHA256 of the script's *contents*, so editing the `utilities` array changes the
hash and `chezmoi apply` re-runs the **whole** installer on machines that already ran the previous version. That is
how a newly added package reaches them — but budget for the 45-120 minute pass noted above, and do not cancel it
(the `install_*()` guards and apt idempotency make most of it a no-op). To pull in just these two packages ahead of
the next apply: `sudo apt install --no-install-recommends --yes sox libsox-fmt-pulse`.

`dot_zshrc.tmpl` must **not** alias `rec` or `play` — both are SoX binaries (`/usr/bin/rec` and `/usr/bin/play`,
from the `sox` package). asciinema previously took both names and shadowed SoX; it now uses the non-conflicting
`record` / `replay` pair. Claude Code was never affected (it spawns via `PATH`, not through an interactive
shell), but the aliases broke testing capture by hand:

```bash
rec -c 1 -r 16000 /tmp/mic-test.wav trim 0 3 && play /tmp/mic-test.wav
```

If SoX picks the wrong driver, force it with `AUDIODRIVER=pulse`.

## SSH Agent Bridge (WSL)

Every SSH key on this setup lives in 1Password on the Windows side. Two mechanisms carry that
across the WSL boundary, and **both work by executing a Windows binary**: the `ssh` →
`ssh.exe` wrapper in `dot_local/bin/executable_ssh`, and `gpg.ssh.program = op-ssh-sign-wsl`
in `dot_gitconfig.tmpl`, which signs every commit.

Neither reaches a program that does SSH *itself* rather than shelling out to `ssh`. go-git
([AutoBump](https://github.com/rios0rios0/autobump)), Go's `x/crypto/ssh`, and libgit2
authenticate by dialing an `AF_UNIX` socket and speaking the agent protocol; they never
execute a binary, so `core.sshCommand` is never consulted and the wrapper is never invoked.
Go cannot dial a Windows named pipe, so for those tools the keys simply do not exist. That is
the whole shape of the bug it produces: signing works, `git push` works, and one tool reports
no usable SSH credential — which reads as that tool losing a key that demonstrably exists.

`dot_config/systemd/user/ssh-agent-bridge.socket` closes the gap. It listens on
`~/.ssh/agent.sock` and, per connection, hands the accepted socket to
`ssh-agent-bridge@.service`, which runs [npiperelay](https://github.com/jstarks/npiperelay)
to copy bytes to and from `\\.\pipe\openssh-ssh-agent`.

**`Accept=yes` is what removes the `socat` dependency.** The usual recipe for this bridge is
`socat UNIX-LISTEN:...,fork EXEC:'npiperelay.exe ...'`; systemd socket activation does the
same three things natively — listen, fork per connection, hand it over on stdio — so the
package is unnecessary, and so is a relay daemon spawned from a shell profile. Private keys
never leave 1Password, so its approval prompt still guards every signature.

Three placement decisions carry the design:

- **`.chezmoiignore` gates on the kernel, not the OS.** `"linux"` alone does not separate WSL
  from bare metal, where there is no Windows agent and the unit would point at an
  `npiperelay.exe` that is never installed. `test-chezmoiignore.sh` substitutes a literal
  kernel so both branches are assertable on any host — otherwise whichever kernel the test
  host happens to run would silently decide the result.
- **`SSH_AUTH_SOCK` is exported from `dot_zshenv.tmpl`, not `dot_zshrc.tmpl`.** The tools that
  need it are the ones a *non-interactive* shell launches (IDE terminals, MCP servers, Claude
  Code's Bash tool), and those read `.zshenv` only. Only the pointer belongs there: systemd
  binds the socket at login through `sockets.target`, and socket activation means the listener
  exists before anything connects. Spawning a relay from the profile would start one per shell.
  The path deliberately matches the Android agent's — both platforms answer `SSH_AUTH_SOCK` at
  `~/.ssh/agent.sock`, with a different provider behind it.
- **The installer is `run_onchange_after_`, not `run_once_before_`.** Existing machines already
  ran every `run_once_` script, so an installer added there would never reach them.

The relay download is pinned by version and verified against the SHA-256 upstream publishes;
a mismatch refuses to install rather than leaving a binary that fails once per connection.

Verify with the **Linux** `ssh-add` — the bare name resolves to the `ssh-add.exe` wrapper,
which would query the Windows agent directly and prove nothing about the bridge:

```bash
/usr/bin/ssh-add -l                              # should list the 1Password keys
systemctl --user status ssh-agent-bridge.socket  # should be active (listening)
```

The bridge needs systemd in WSL, which `chezmoi apply` turns on (see "systemd on WSL"). Until
WSL boots with it, the installer warns and exits 0, leaving `SSH_AUTH_SOCK` pointing at nothing,
and the first apply after the restart sets the bridge up.

## Windows Package Detection (winget list, Not export)

`Install-PackageList` in `run_once_before_windows-001-install-dependencies.ps1` decides what is
already installed with `winget list --id <id> --exact --source <source>`, one call per entry
(about 1.3 s each). It used to read `winget export` once, which looked cheaper and was wrong:
export leaves out packages that are installed -- on the machine this was found on it omitted
GIMP, Codex, yq, ShellCheck, the Copilot CLI and the EA app -- so every run installed them again.

| Rule | Why |
|------|-----|
| Every entry is an **exact** ID in its source | Detection and install both pass `--exact`. Without it `winget install` accepts a partial match, which is how `PerformanceTest` quietly meant `PassMark.PerformanceTest` while never counting as installed. Check a new entry with `winget show --id <id> --exact --source <source>` |
| `msstore:<id>` names a Microsoft Store app | Spotify is `msstore:9NCBCSZSJRSB`: the Store edition is what the machine had, and the `Spotify.Spotify` installer refuses to run beside it (exit code 29, logged as `A Windows Store install of Spotify is already on the system`). winget matches a Store app to its ID only when asked in the `msstore` source |
| A failed install is a `WARN`, never "installed successfully" | The script prints winget's exit code and ends with the list of everything that failed, RustDesk included. It still exits 0, because a failing `run_once_before_` script aborts the apply before any file is written; the cost is that a failed package is retried only when the script changes |

`make test-install-dependencies-windows` runs `Install-PackageList` against a stubbed `winget`.

## Windows Fonts (Per User, Before Every Apply)

`run_before_windows-003-install-fonts.ps1` installs MesloLGS NF -- the face Windows Terminal's
profiles name -- and the FiraCode and Meslo Nerd Fonts for the current user: into
`%LOCALAPPDATA%\Microsoft\Windows\Fonts`, registered under `HKCU`, which Windows 10 1809 and
later load without administrator rights.

| Rule | Why |
|------|-----|
| Per user, never `$env:WINDIR\Fonts` | The machine-wide copy needed an elevated shell. The `run_once_` version warned and exited 0 without one, chezmoi recorded it as done, and Windows Terminal opened with "MesloLGS NF" not found for good |
| `run_before_`, returning at once while every family is installed | A family missing from both the user's and the machine's fonts folder is installed on the next apply, whatever happened before; a family a machine-wide install already provides is left alone |
| A failed download warns and exits 0 | The next apply retries it anyway, so it never stops an apply |
| Never `New-Item -Force` on the `HKCU` fonts key | On an existing registry key it recreates the key, dropping every other font registered there |

`make test-install-fonts-windows` covers it under pwsh, with the downloads and the registry stubbed.

## RustDesk on Windows (GitHub Release, Not winget)

RustDesk is the remote-access tool, and it must **not** go back into the `$utilities` winget
list: its publisher had every `RustDesk.RustDesk` version removed from winget in March 2026,
after Microsoft's scan falsely flagged it as malware and it could not be allowlisted again
([microsoft/winget-pkgs#352094](https://github.com/microsoft/winget-pkgs/issues/352094)).
`winget install RustDesk.RustDesk` now fails with `No package found`.

`Install-RustDesk` in `run_once_before_windows-001-install-dependencies.ps1` installs the
release MSI instead, through `Save-VerifiedDownload`:

| Check | Why |
|-------|-----|
| SHA-256 pinned to one MSI | Pins the exact bytes. RustDesk publishes no checksum file, so the pin is GitHub's asset `digest`, which on its own proves only that GitHub served what GitHub holds |
| Authenticode signature `Valid`, signer `PURSLANE` | The provenance the pin lacks: a pin bumped from a tampered release still installs nothing RustDesk did not sign. Verified 2026-09-29: the `1.4.9` MSI and the working manual install share signer thumbprint `4230334F8A7DD84E50D0273EF379E8B4A82F5DA5` |
| Skipped when an Uninstall entry is named `RustDesk` | The `.exe` installer registers the key `RustDesk`, the MSI its product code, and both use that display name, so a manual install is left alone instead of getting a second copy beside it |

The MSI is per-machine (`ALLUSERS=1`) and registers the `RustDesk` service, so it runs with
`/passive`, not `/qn`: a non-elevated apply then raises a UAC prompt instead of failing
silently. To bump the pin, take the new MSI's `digest` from the release API; the signer check
needs no change unless RustDesk changes certificates.

## Age Keys (One Per Purpose)

Every age key `chezmoi apply` puts on a machine has one job, and lives in 1Password's `Private`
vault as a Secure Note whose `private key` field holds the whole identity file `age-keygen -o`
writes. `.chezmoidata/age-keys.yaml` names each item and each key's public half:

| Key | File | Item | Where |
|-----|------|------|-------|
| chezmoi | `~/.ssh/chezmoi` | `chezmoi.age` | Linux/WSL and Windows: decrypts every `encrypted_*.age` file |
| OmniRoute backups | `~/.ssh/omniroute-backup-key` | `omniroute-backup.age` | WSL alone, where `omniroute-backup` runs |

Neither is the SSH key that signs commits. The chezmoi files were encrypted to that key until
2026-10-27; they are re-encrypted to `chezmoi.age` now, and that key still opens only the older
versions in the repository's history.

**Keep these:**

1. **The export scripts run before every apply, and touch 1Password only when a key differs.**
   `run_before_linux-005-export-private-key.sh.tmpl` and
   `run_before_windows-004-export-private-key.ps1.tmpl` compare each file with the `# public key:`
   comment `age-keygen` writes into it -- no age binary needed, which a first Windows apply has
   only just installed -- and fetch the item when it is missing or holds another key. As
   `run_once_` scripts they could not recover: the Windows one called `op read` without
   `--account my`, which fails with two accounts in the CLI, and reported that as success, because
   a native command's failure does not fail a PowerShell script; chezmoi recorded it as done, and
   every apply after that died at `.aws/config` with `age: error: reading ".../.ssh/chezmoi"`.
2. **A key is written only once it is the right one.** It is staged beside the target, checked
   for an `AGE-SECRET-KEY-1` line and the expected public key, and renamed over the target, so a
   failed or wrong read leaves the previous file as it was.
3. **A missing chezmoi key fails the apply; a missing backup key only warns.** The apply decrypts
   nothing without the first and needs none of the second. Both are retried on the next apply.
4. **Nothing deletes `~/.ssh`.** The Linux script used to `rm -rf` it before writing the key; on
   WSL that directory also holds the SSH agent bridge's socket and the backup key.
5. **`chezmoi add --encrypt` encrypts to `~/.age_recipients`** (`age.recipientsFile` in
   `.chezmoi.yaml.tmpl`, rendered from `age-keys.yaml` by `dot_age_recipients.tmpl`). Without a
   recipient age stops with `missing recipients`. Like any config change it reaches a machine
   only with `chezmoi init` (see "Config Data Comes From `chezmoi init`"); decrypting never reads
   it. Encrypted files end in `.age` and must show `"age encrypted file, ASCII armored"` when
   checked with `file`.

**Rotating a key:** create the new item the same way (`age-keygen`, then `op item create` from a
JSON template on stdin, so the private key never reaches an argument list), put its reference and
public key in `age-keys.yaml`, and re-encrypt what the old key protected: for the chezmoi key, pipe
each `encrypted_*.age` through `age -d -i <old> | age -e -a -r <new>` and check the new file
decrypts to the same SHA-256. The next apply on each machine replaces the key file by itself.

`make test-export-keys` covers the Linux script against a stubbed `op.exe`, and
`make test-export-key-windows` the Windows one under pwsh.

## Kubeconfig Permissions (the Tarball Stays Non-Private)

`private_dot_kube/` deploys `~/.kube` as `0700`, and `encrypted_private_config.age` deploys
`~/.kube/config` as `0600`. Helm checks the kubeconfig's mode on every invocation, and the Oh My
Zsh `helm` plugin runs `helm completion zsh` at every shell start, so a group- or world-readable
kubeconfig prints two `WARNING: Kubernetes configuration file is ... insecure` lines in every new
terminal. Keep the fix in the source attribute: chezmoi manages the mode, so a `chmod` on the
target is reverted by the next apply.

**`encrypted_config-files.tar.age` deliberately carries no `private_`; do not add one to match its
sibling.** The folder watcher (`dot_scripts/executable_linux-toolbox-watch-compress-folders.sh`)
rebuilds that tarball from `~/.kube/config-files` on every change and re-adds it with
`chezmoi add --encrypt`. `tar` writes it `0644` under the default umask, and re-adding a `0644`
file over a `private_` entry makes chezmoi ask
`adding .kube/config-files.tar would remove private attribute, continue?`. The watcher runs
headless (`nohup … &>/dev/null &` from `dot_zshrc.tmpl`), so nothing can answer: the add fails,
`archive_dir` deletes the archive anyway, and the source keeps the stale tarball. The
`~/.kube/config-files` backup silently stops; the only trace is
`/tmp/linux-toolbox-watch-compress-folders.log`, and no apply, lint or test fails.

The `0700` directory is what protects the tarball: other users cannot traverse into `~/.kube`,
whatever the file's own mode. To make the tarball private anyway, change the watcher first (wrap
its `tar -cf` in `umask 077`); the next re-add then gains `private_` by itself, because chezmoi
adds the attribute without prompting. Renaming the source file alone springs the trap above.

<!-- chlog:start -->
## Changelog (chlog) — MANDATORY

If the repository you are working in uses chlog (a `.chlog.yaml` or `.chlog.yml`
config file, or a `.changes/` directory, exists at the project root), the
following is binding and ALWAYS applies: whenever you make ANY change, you MUST
create a changelog fragment as part of the same change — automatically, without
being asked, before committing.

- Do NOT edit CHANGELOG.md directly; it is generated from fragments.
- Create the fragment with:
  `chlog new --kind <Kind> --body '<past-tense description>'`
- Write an apostrophe inside the single-quoted body as `'\''`.
- Valid kinds: Added, Changed, Deprecated, Removed, Fixed, Security
- Choose the kind that best matches the change (e.g., new feature → Added,
  bug fix → Fixed, behavior change → Changed, removal → Removed, security fix → Security).
- If the change is backward-INCOMPATIBLE with the public API (a breaking
  change), you MUST add the `--breaking` flag:
  `chlog new --kind <Kind> --breaking --body '<past-tense description>'`.
  This is the ONLY thing that triggers a major version bump — the kind alone
  never does (per SemVer, major = incompatible change). When unsure whether a
  change breaks compatibility, ask the user instead of guessing.
- Fragments are YAML files in `.changes/unreleased/`; stage them with your commit.
- `chlog check` fails the build when a fragment is missing — never skip it.
<!-- chlog:end -->
