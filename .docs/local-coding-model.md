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

It runs again whenever the pinned version, the model or the unit's settings change.

## Usage

```bash
claude-local                                   # an interactive session on the local model
claude-local -p "add a test for Subtract"      # print mode, like `claude -p`
CLAUDE_LOCAL_MODEL=qwen3.6:27b claude-local    # another pulled model, for one session
```

The first launch shows Claude Code's onboarding once, because the session runs in its own profile
(`~/.claude-local`), and its trust prompt once per project, as any new profile would.

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
  `systemctl --user status ollama`.
- **Exit status.** `ollama launch` keeps running as the parent of `claude`, and reports any
  non-zero exit as `Error: exit status N` with status 1. Ctrl+C is unaffected: Claude Code reads it
  as input, so it interrupts a reply as usual.

## Another GPU on the network

Not wired up yet. `OLLAMA_HOST=<host>:<port> claude-local` reaches another Ollama server, but
`claude-local` still declares the local window from the data file, and on this machine an SSH
tunnel is easy to get wrong: `ssh` is the `ssh.exe` wrapper and WSL runs in NAT mode, so
`ssh -L` opens the port on Windows' loopback, which WSL cannot reach. A tunnel would need
`/usr/bin/ssh` through the [SSH agent bridge](../CLAUDE.md), or mirrored networking.

## References

- [Ollama: Claude Code integration](https://docs.ollama.com/integrations/claude-code)
- [Ollama: Anthropic API compatibility](https://docs.ollama.com/api/anthropic-compatibility)
- [Ollama: context length](https://docs.ollama.com/context-length)
- [Claude Code: environment variables](https://code.claude.com/docs/en/env-vars)
- [Claude Code: model configuration](https://code.claude.com/docs/en/model-config)
