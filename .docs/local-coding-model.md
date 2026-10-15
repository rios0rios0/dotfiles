# Local Model for Claude Code (`claude-local`)

`claude-local` runs Claude Code on an Ollama model served from this machine's NVIDIA GPU. It
changes nothing outside its own process: the regular `claude`, its login and ccswitch's account
rotation stay exactly as they are, and both can run side by side.

## When it is installed

On every Linux machine -- WSL or bare metal -- that has an NVIDIA driver (`nvidia-smi` on `PATH`),
unless `.chezmoidata/local-llm.yaml` sets `enabled: false`, globally or for one device.
`chezmoi apply` then runs `run_onchange_after_linux-009-setup-ollama.sh`, which:

1. downloads the pinned Ollama release, checks it against the digest upstream publishes, and
   unpacks it into `~/.local/share/ollama/<version>` (no root, no system user);
2. starts `ollama.service` as a **user** unit, rendered from the same data file;
3. pulls the model (about 18 GB the first time; Ollama itself is 1.4 GB);
4. loads the model once and fails the apply if it landed on the CPU although the GPU had room
   -- see [Troubleshooting](#troubleshooting) for why that check exists. A GPU that a game or
   the desktop has filled only warns.

It runs again whenever the pinned version, the model or the unit's settings change, and once
systemd starts. A WSL distribution can boot without systemd -- Kali's does until `chezmoi apply`
turns it on in `/etc/wsl.conf` -- and the installer then stops after step 1, to finish on the first
apply after WSL restarts with it.

Ollama listens on `0.0.0.0:11434` so clients on the local network can connect to the machine's LAN
address, and so Tailscale Serve can forward requests without Ollama rejecting the remote `Host`
header. The API has no authentication: any device allowed through the host firewall can run
inference, pull models and delete models. Keep port `11434` restricted to networks and devices you
trust.

On WSL 2, binding to `0.0.0.0` does not by itself make the service reachable from the LAN. WSL's
default NAT mode requires a Windows port proxy and firewall rule; Windows 11 mirrored networking
can expose WSL directly, with an inbound Hyper-V firewall rule. See Microsoft's [WSL networking
guide](https://learn.microsoft.com/windows/wsl/networking) for the setup that matches the Windows
version and networking mode.

## Usage

```bash
claude-local                                   # an interactive session on the local model
claude-local -p "add a test for Subtract"      # print mode, like `claude -p`
CLAUDE_LOCAL_MODEL=qwen3.6:27b claude-local    # another pulled model, for one session
```

The first launch shows Claude Code's onboarding once, because the session runs in its own profile
(`~/.claude-local`), and its trust prompt once per project, as any new profile would.

The profile looks like the regular `claude`: `chezmoi apply` keeps the same theme, fullscreen
renderer and status line in `~/.claude-local/settings.json`, so a theme picked during onboarding
lasts only until the next apply. The status line shows the local model and its context window,
and no plan limits. See "Claude Code and Codex Look" in `CLAUDE.md`.

When ccswitch reports that no enrolled account has capacity left, `claude` and `claudex` say so
before launching and point at `claude-local`. They only point: nothing switches models without
being asked.

## Settings

Everything lives in `.chezmoidata/local-llm.yaml`, which chezmoi reads on every apply -- no
`chezmoi init` needed:

| Key | Default | What it controls |
|-----|---------|------------------|
| `model` | `qwen3.8:27b` | The model, for every Claude Code tier at once |
| `contextTokens` | `65536` | Both `OLLAMA_CONTEXT_LENGTH` and `CLAUDE_CODE_MAX_CONTEXT_TOKENS`, from one value |
| `maxOutputTokens` | `8192` | The reply reservation Claude Code subtracts from the window |
| `kvCacheType` | `q8_0` | KV cache precision; half the memory of the `f16` default |
| `keepAlive` | `15m` | How long an idle model stays in VRAM before the GPU is given back |
| `rules` | `code-style`, `git-flow`, `testing` | The global rules a local session keeps |
| `tools` | `Bash`, `Read`, `Edit`, `Write`, `Glob`, `Grep` | The tools it gets |
| `shareOnTailnet` | `true` | Whether this machine's server is shared on the tailnet for `claude-remote` |
| `devices` | none | Per-device overrides of any key above, by chezmoi `deviceName` |

## Why the session is lean

The window has to hold everything Claude Code sends before the first prompt. Measured with
`/context` on 2026-10-12 (Claude Code `2.1.296`):

| Profile | dotfiles repository | ccswitch repository |
|---------|--------------------|---------------------|
| Regular profile | 72.8K tokens | 50.7K tokens |
| Lean profile (`claude-local`) | 37.2K tokens, 7.1K free | 18.5K tokens, **25.9K free** |

Three things account for the difference, and each needed its own fix:

- **Tool schemas.** For a model it does not recognise, Claude Code sends every tool schema with
  every request instead of deferring the rarely used ones: 27K tokens. `--tools` limits a local
  session to six (5.8K).
- **Global rules.** A separate `CLAUDE_CONFIG_DIR` does not drop `~/.claude/rules`: for any
  project under `$HOME`, Claude Code reads that directory as the rules of the ancestor directory
  `~`. `claudeMdExcludes` keeps only the rules listed in the data file.
- **The reply reservation.** Claude Code reserves room for a reply plus about 13K before it
  auto-compacts. An unrecognised model gets 32K by default, which left nothing of a 64K window;
  `maxOutputTokens: 8192` makes it 21.2K.

A repository whose own `CLAUDE.md` is as large as this one's (26.9K tokens) leaves too little room
for a 64K window and is better served by the regular `claude`.

## Performance on this machine

Measured on 2026-10-12: RTX 5090 Laptop GPU (24 GB, also driving the display), Ollama `0.40.3`,
`qwen3.8:27b` at a 64K window with a `q8_0` cache:

| Measure | Result |
|---------|--------|
| Placement | 100% GPU, 21.8 GB of VRAM in use at peak (about 1.2 GB of it the Windows desktop) |
| Prompt processing | 1,194 tokens/s (9,866 tokens in 8.3 s) |
| Generation | 27.9 tokens/s |
| Between turns | the prompt cache is reused; only new tokens are processed |
| End to end | a 9-turn edit-test-run task in 45 s |
| On the CPU instead | 55 s for a one-word reply |

The GPU is shared with Windows. A game holding 10 GB of VRAM leaves too little for the model, and
Ollama then runs part of it on the CPU: the installer reports that as a warning, and `ollama ps`
shows the split.

## Troubleshooting

- **Where does the model run?** `ollama ps`: the `PROCESSOR` column must read `100% GPU`.
- **Ollama found no GPU.** `journalctl --user -u ollama | grep 'inference compute'` should show
  `library=CUDA`. A `GPU discovery` failure with `signal: bus error` means a damaged install: a
  WSL VM that went down shortly after an install once left the two `libcublasLt` libraries
  truncated under a marker that said the install was complete, and CUDA discovery then crashed on
  every start while Ollama quietly served from the CPU. The installer now writes the marker only
  after the files are on disk, re-verifies every file against a digest manifest whenever it runs,
  and reinstalls when one no longer matches. To run it now:
  `chezmoi execute-template < "$(chezmoi source-path)/.chezmoiscripts/run_onchange_after_linux-009-setup-ollama.sh.tmpl" | bash`
- **The server is not running.** `claude-local` starts the user unit on demand; otherwise
  `systemctl --user status ollama`. When systemd itself is not running, `claude-local` says so,
  and `systemctl` fails with `Failed to connect to user scope bus via local transport`: on WSL,
  `chezmoi apply` turns systemd on in `/etc/wsl.conf`, then `wsl.exe --shutdown` and a second
  apply start it and finish the setup, model download included.
- **Exit status.** `ollama launch` keeps running as the parent of `claude`, and reports any
  non-zero exit as `Error: exit status N` with status 1. Ctrl+C is unaffected: Claude Code reads it
  as input, so it interrupts a reply as usual.

## Another machine's GPU (`claude-remote`)

`claude-remote` is `claude-local` with the model served by another machine on the tailnet. Claude
Code itself still runs here: every file it reads or edits and every command it runs is on this
machine, and only inference happens on the other one.

```bash
claude-remote                                  # an interactive session on the other machine's GPU
CLAUDE_REMOTE_HOST=desktop claude-remote       # a machine named explicitly
```

How the two machines meet:

1. Both are on the tailnet (see "Tailscale" in [CLAUDE.md](../CLAUDE.md)). A WSL machine is on it
   through Windows' Tailscale client, logged in once with its app; WSL reaches that client's CLI
   through the `tailscale` wrapper. A bare-metal machine runs `tailscaled`, which `chezmoi update`
   installs and logs in.
2. A machine with the local model shares its server on the tailnet's port 11434, unless
   `shareOnTailnet` in `.chezmoidata/local-llm.yaml` says otherwise. It is `tailscale serve`, never
   Funnel; on WSL, Windows' client forwards to Windows' loopback, which WSL hands on to Ollama;
   run `tailscale-up` in WSL once Windows is logged in. Ollama listens on all interfaces for LAN
   access and has no authentication, so firewall rules and the tailnet policy define who can run,
   pull and delete models. WSL 2 may need mirrored networking or a Windows port proxy for LAN
   clients; see [When it is installed](#when-it-is-installed).
3. `claude-remote` picks the first online machine that answers there, or the one
   `CLAUDE_REMOTE_HOST` names.

Before handing over, it loads the model on that machine and reads back how the server holds it:

- **A different context window stops the launch.** `claude-local` declares the window from this
  machine's data file. A server rendered from an older checkout, or with a per-device override,
  would truncate the prompt where Claude Code expects to compact it. Run `chezmoi update` there.
- **A model partly on the CPU only warns.** A GPU busy with a game leaves part of the model on
  that machine's CPU, where every request still succeeds, many times slower.

**A WSL machine serves only while its WSL runs**, and Windows stops WSL a few seconds after the
last WSL terminal closes. To use a desktop's GPU from the laptop, open a WSL terminal on the
desktop (RustDesk will do) and leave it open: Ollama starts with it. The desktop stays on the
tailnet meanwhile, because the client is Windows'; `tailscale set --unattended=true` there keeps
it on after its user signs out, and before the first sign-in after a reboot.

The other machine's GPU has the same 24 GB as this one, so it runs the same model, not a bigger
one: it is a second worker, useful while this GPU is busy, on battery, or already serving a run.

## Delegating a task (`claude-local-task`)

An agent that hands a task to the local model -- `ollama-local` and `ollama-remote` in the
[aifiles](https://github.com/rios0rios0/aifiles) agents -- runs it through `claude-local-task`:

```bash
claude-local-task brief.md            # on this machine's GPU
claude-local-task --remote brief.md   # on another machine's, through claude-remote
```

The model runs unattended with every permission check off, as the caller's own session does, so
it can run whatever the task needs. Nobody watches it, so instead of restricting it,
`claude-local-task` returns all of it to the caller:

- **every action**, in order, with its result: each command and its output, each file read or
  written, a write outside the repository flagged as one;
- **the change**, measured between snapshots of the working tree taken before and after the run,
  untracked files included. The snapshots go through a scratch copy of the index, so the
  caller's own index is never touched, and edits that were already in the tree are never
  attributed to the run;
- **one command that undoes exactly that change** (`git diff --binary <before> <after> | git
  apply -R`), and one that shows it;
- **the transcript**, which Claude Code keeps under `~/.claude-local/projects`.

It prints the audit in short and saves it in full under `~/.claude-local/audits`. What an audit
cannot take back is whatever left the working tree -- a commit, a push, a request to a server, a
write somewhere else. Those show up in the action list and as a moved HEAD, and nowhere else.

Measured on this machine: a two-file Go change with tests, 6 turns, 46 seconds.

## References

- [Ollama: Claude Code integration](https://docs.ollama.com/integrations/claude-code)
- [Ollama: Anthropic API compatibility](https://docs.ollama.com/api/anthropic-compatibility)
- [Ollama: context length](https://docs.ollama.com/context-length)
- [Claude Code: environment variables](https://code.claude.com/docs/en/env-vars)
- [Claude Code: model configuration](https://code.claude.com/docs/en/model-config)
- [Tailscale: `tailscale serve`](https://tailscale.com/docs/reference/tailscale-cli/serve)
- [Tailscale: Windows with WSL 2](https://tailscale.com/kb/1295/install-windows-wsl2)
- [Tailscale: why resolv.conf gets overwritten](https://tailscale.com/docs/reference/faq/dns-resolv-conf)
