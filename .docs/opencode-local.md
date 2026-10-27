# OpenCode V2 Through OmniRoute

OpenCode is the client of the local [OmniRoute](omniroute-local.md) gateway, and on Linux it runs
as `ocode`, the personal fork's build (see [Where the CLI comes from](#where-the-cli-comes-from)).
`chezmoi apply` renders `dot_config/opencode/opencode.json.tmpl` to
`~/.config/opencode/opencode.json`, making OmniRoute the primary provider and
`omniroute/auto/coding` the default model. No model list lives in this repository for OpenCode:
it discovers the catalog from the gateway's own `/v1/models`, which serves exactly what the API
key's policy allows, so a model, or a whole new provider, added in OmniRoute's dashboard appears
without a change here.

## What is configured

| Part | Where it comes from |
|------|---------------------|
| Provider | `providers.omniroute`: `baseURL` is `.chezmoidata/omniroute.yaml`'s `baseUrl` with `/v1`, and the key is the `{env:OMNIROUTE_API_KEY}` reference |
| Model list | live from the gateway; the `omniroute/*` entries in the model picker and `ocode models` |
| Default model | `omniroute/auto/coding`: the gateway picks the upstream |
| MCP servers | context7 (remote, every platform) and Chrome DevTools (local, Linux only, pinned like Claude Code's) |
| Permissions | the same shell, read and edit allowances as the Claude Code side, as V2 ordered entries |
| Rules | `~/.config/opencode/AGENTS.md` (environment reality) and `rules/` (standards), synced by aisync, plus every project's `CLAUDE.md` through `instructions` |
| Reference | `dotfiles` points at the chezmoi source, so a session can read the dotfiles that rendered the configuration |
| Terminal look | `~/.config/opencode/cli.json` |

The key is the `cred:OMNIROUTE_API_KEY` field of the device note: the credential loader exports
`OMNIROUTE_API_KEY` in every shell, and OpenCode substitutes it when it loads the file. The
repository itself never holds it.

AI content is not part of this configuration. `~/.config/opencode/AGENTS.md`, `rules/`,
`agents/`, `commands/` and `skills/` are synced by aisync (the `opencode` tool in the aifiles
config), like the equivalent `~/.claude` tree; chezmoi renders only
`opencode.json` and `cli.json` here. The local plugin
`~/.config/opencode/plugins/no-claude-skills.ts` filters the Claude-compatible
`~/.claude/skills` source out of the skill catalog (OpenCode V2 ignores the
`OPENCODE_DISABLE_CLAUDE_CODE_*` variables, anomalyco/opencode#36990), so skills load only from
`~/.config/opencode/skills`.

Upstream's restore of those variables (sst/opencode#51888) was closed unmerged; the gate now
lives on the personal fork `rios0rios0/opencode`, branch `reworked` (commit
"feat(core): restore OPENCODE_DISABLE_CLAUDE_CODE for compatibility roots"), which gates the
`~/.claude` compatibility roots at discovery. `ocode` is built from that branch, but nothing
exports the variable yet, so the plugin is still the stopgap; to switch, export
`OPENCODE_DISABLE_CLAUDE_CODE=1` from `dot_zshenv.tmpl` and delete the plugin.

## Where the CLI comes from

On Linux the CLI is `ocode`: OpenCode built from the personal fork `rios0rios0/opencode` (branch
`reworked`), which adds the OmniRoute provider plugin and the `OPENCODE_DISABLE_CLAUDE_CODE`
gate. `run_after_linux-006-build-ocode.sh` builds it into `~/.local/bin/ocode`. It reads the same
`~/.config/opencode/opencode.json` and `cli.json` that upstream's `opencode` would; that binary is
not installed. The build script is Linux only, so Windows and Android get the configuration
without a CLI. How the build works is in [The fork build (`ocode`)](#the-fork-build-ocode).

## Using it

```bash
ocode                          # in a project; the picker lists every model the key allows
ocode models                   # the full catalog, with the omniroute/* entries among them
```

Model ids are OmniRoute's own behind the provider's `omniroute/` prefix: `omniroute/auto/coding`,
`omniroute/codex/...`, `omniroute/nvidia/...`.

A reasoning model is listed once, and its effort is a variant of it: `ctrl+t` cycles the variants
in the TUI, and `ocode run -m omniroute/<model>#high` picks one for a single run. The variants are
the `capabilities.effort_tiers` the gateway reports for the model, so a model that reports none has
none. OmniRoute would also list each tier as a model of its own (`<model>-high`), which the Compose
file turns off with `OMNIROUTE_DISABLE_THINKING_LEVEL_VARIANTS`. Providers whose own model ids carry
the tier, such as Codex's `*-high`, keep those rows: they are models, not variants.

## The fork build (`ocode`)

`run_after_linux-006-build-ocode.sh` rebuilds `ocode` from the checkout at
`~/Development/github.com/rios0rios0/opencode` whenever that checkout's HEAD moved, and installs
it as `~/.local/bin/ocode`; see the "Fork Build (`ocode`)" part of the main `CLAUDE.md` for the
mechanics. The build pins the client identity the Console reads from the
User-Agent -- `OPENCODE_CHANNEL=feat-provider-omniroute` and a build-stamped
`OPENCODE_VERSION=<release>-reworked.<%y%m%d%H%M>`, e.g. `2.1.4-reworked.2610241230`, where
`<release>` is the upstream release the checkout is built on (its `packages/cli/package.json`
`version`, or 2.0.0 with a warning when that names no release) -- because the free tier refuses
client versions below 1.18.0, which a bare branch build's `0.0.0-<branch>-<time>` preview version
is; the channel keeps the fork's service registration, port and database its own, and the stamp
makes each rebuild replace the background service on the next launch. bun, its build runtime, comes from
`install_bun` into `~/.bun` (PATH block in `dot_zshenv.tmpl`), and the builder falls back to
`~/.bun/bin/bun` itself, so the first apply after the install builds without waiting for a new
shell.

The build runs on the bun the checkout pins (`packageManager` in its `package.json`), as
upstream OpenCode's CI does, because a newer bun can reject what the pinned one installs (1.4.4
refused a patch file the fork's 1.4.2 pin applies). That is the machine's bun when it is that
version; otherwise the first build that needs it downloads that version from bun's GitHub
release into `~/.cache/ocode-bun/<version>/`, verified against the release's `SHASUMS256.txt`.
With it, the builder runs `bun install --frozen-lockfile` in the checkout before every build,
which the fork's build assumes has happened. A pin that cannot be read or fetched (no network)
warns and falls back to the machine's bun.

A running `ocode` -- the TUI or the server it spawns -- executes `~/.local/bin/ocode`, the file
the build replaces. The builder looks for processes running **that** file (through
`/proc/<pid>/exe`, so an `ocode` started from another path is left alone) and asks before killing
them, because they are somebody's session. The answer never decides whether the build happens:
the install stages the new binary beside the target and renames it into place, so the running
session is not disturbed and keeps the binary it started with until it restarts. Answering no --
or applying unattended, where nothing answers -- leaves the session alone and builds anyway, and
an `ocode` started *while* the build runs is safe for the same reason. `make test-ocode` covers
every path of the prompt and the mid-build race.

The `rebuild-ocode` zsh function runs the same script on demand, resolving it through
`chezmoi source-path`, so a build can be caught up after pulling the fork checkout -- or when an
apply found nothing to build -- without a whole apply. `make test-zshrc-functions` covers it.

## The web UI on the tailnet

OpenCode's web UI is the client a phone uses: the server renders it, and the official binary is
a glibc build Termux's bionic cannot start, so there is nothing to install on the phone. What the
phone needs is a reachable server and a session.

`tailscale-up` shares it, the same way it shares Ollama and for the same reason: `tailscale serve
--bg --tcp=<port>` puts the forward in the client's own state, so it comes back with the service,
and it never uses Funnel. Both settings live in `.chezmoidata/opencode.yaml`, read through
`.chezmoitemplates/lib-opencode.tmpl`:

| Key | Default | What it does |
|-----|---------|--------------|
| `shareOnTailnet` | `true` | whether `tailscale-up` forwards the port |
| `webPort` | `41320` | the port the fork's service listens on -- its channel's default |
| `devices.<deviceName>` | `{}` | per-device overrides, laid over key by key like `local-llm.yaml`'s |

**The service keeps listening on loopback.** `ocode service set hostname 0.0.0.0` is not part of
this: on WSL, Windows' client forwards to Windows' `localhost`, which WSL's localhost relay hands
to the service's `127.0.0.1` socket, and on bare metal the forward names `127.0.0.1` directly. The
port therefore stays closed to the Wi-Fi network, and the tailnet's ACLs decide who reaches it.

Pair a device with the reachable address in the link, never the loopback one the TUI prints:

```bash
tailscale status --json | jq -r '.Self.DNSName'   # <machine>.<tailnet>.ts.net.
ocode pair --url "http://<machine>.<tailnet>.ts.net:41320"
```

`--url` is what replaces `127.0.0.1` in the link, so the QR code carries the address the phone can
actually dial (`tailscale ip -4` gives the `100.x.y.z` form, which works as well). Opening the link
on the phone signs it in with a session cookie and loads the UI.

The link is one-time and expires in 5 minutes; the session it grants lasts 30 days. Changing the
server password signs every session out, and `ocode service set password ...` is how a session is
revoked. The pairing page is a navigation, and the cookie carries no `Secure` flag, which is why
the plain-TCP forward is enough here.

Switching `shareOnTailnet` off stops `tailscale-up` from re-creating the forward; it does not
remove the one already in the client, because a `serve` entry outlives the repository that set it.
Remove it with `tailscale serve --tcp=41320 off`. A share left pointing at a stopped service
answers connections with nothing behind them, which is harmless: the next `ocode` start serves the
UI again.

## When models are missing

- **The gateway is down.** While OmniRoute does not answer, the provider serves no models;
  start it with `docker compose up -d` from `local-services/omniroute/`. Nothing else in
  OpenCode is affected.
- **The key is missing.** In an environment without the credential loader (a cron job, an
  IDE), `{env:OMNIROUTE_API_KEY}` substitutes empty, the gateway answers 401 and the models
  disappear. Run OpenCode from an interactive shell, or export the key first.
- **A model the key does not allow.** The list is OmniRoute's key policy; allow the model or
  the combo in its dashboard rather than adding anything here.
- **Nothing at all is loaded.** V1 habits fail silently: the MCP field is `environment`, not
  `env`, and a key written as `${OMNIROUTE_API_KEY}` stays literal and fails authentication.
  `make test-opencode` guards both by rendering the template on each platform and checking
  every field, and `ocode debug config` shows what was actually loaded.

## References

- [The gateway and its keys](omniroute-local.md)
- [OpenCode configuration](https://opencode.ai/docs/config)
