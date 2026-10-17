# Local Model Server (Ollama)

Ollama serves a coding model from this machine's NVIDIA GPU. It is one of OmniRoute's providers:
Claude Code reaches it through `claude-omni`, which also reaches another machine's GPU and the cloud
providers. See [OmniRoute for Claude Code](omniroute-local.md) for the launcher; this page covers
the server.

## When it is installed

On every Linux machine -- WSL or bare metal -- that has an NVIDIA driver (`nvidia-smi` on `PATH`),
unless `.chezmoidata/local-llm.yaml` sets `enabled: false`, globally or for one device.
`chezmoi apply` then runs `run_onchange_after_linux-009-setup-ollama.sh`, which:

1. downloads the pinned Ollama release, checks it against the digest upstream publishes, and
   unpacks it into `~/.local/share/ollama/<version>` (no root, no system user);
2. starts `ollama.service` as a **user** unit, rendered from the same data file;
3. reads the server's start-up log -- one `inference compute` line per backend, `library=cpu`
   alone meaning no accelerator answered -- and fails the apply when no other backend is there:
   see [Troubleshooting](#troubleshooting) for why that check exists. Loading a model to see
   where it landed is **not** how this is done anymore: an apply loads nothing, and the model
   loads on the first request that needs it, a cold start of about 20 seconds. A GPU a game has
   filled only warns, forecast from the free VRAM the log reports against the model's size;
4. pulls the model (about 18 GB the first time; Ollama itself is 1.4 GB).

It runs again whenever the pinned version, the model or the unit's settings change, and once
systemd starts. A WSL distribution can boot without systemd -- Kali's does until `chezmoi apply`
turns it on in `/etc/wsl.conf` -- and the installer then stops after step 1, to finish on the first
apply after WSL restarts with it.

Ollama listens on `127.0.0.1:11434`, and the IPv4-specific address is load-bearing on WSL. The
family of the server's listening socket decides the family WSL's localhost forwarding publishes on
the Windows side: a dual-stack `0.0.0.0` bind appears there on `::1` only, and Docker Desktop --
which reaches this machine as `host.docker.internal`, dialing Windows' IPv4 loopback -- then gets
connection refused. `127.0.0.1` publishes Windows' `127.0.0.1`, so OmniRoute's container connects.
Tailscale is unaffected either way: Windows' client shares the server with `tailscale serve` to
`localhost:11434`, which names both families. The API has no authentication: anything that can
reach that port can run inference, pull models and delete models -- on WSL that is every process on
the Windows side, so keep the tailnet share to devices you trust.

## Settings

Everything lives in `.chezmoidata/local-llm.yaml`, which chezmoi reads on every apply -- no
`chezmoi init` needed:

| Key | Default | What it controls |
|-----|---------|------------------|
| `model` | `qwen3.8:27b` | The model the server pulls, and the one `claude-omni` runs on each GPU |
| `contextTokens` | `65536` | Both `OLLAMA_CONTEXT_LENGTH` and the window `claude-omni` declares for every GPU model, from one value |
| `kvCacheType` | `q8_0` | KV cache precision; half the memory of the `f16` default |
| `keepAlive` | `15m` | How long an idle model stays in VRAM before the GPU is given back |
| `shareOnTailnet` | `true` | Whether this machine's server is shared on the tailnet, for OmniRoute on another machine |
| `devices` | none | Per-device overrides of any key above, by chezmoi `deviceName` |

The window has to be one value because nothing else can learn it: Ollama allocates it per server,
Claude Code reads no window from a gateway, and OmniRoute advertises its 128000-token fallback for
every Ollama model. A session declaring more than the server allocates would grow past the point
where Ollama truncates the prompt -- silently -- before Claude Code compacts it.

## Performance on this machine

Measured on 2026-10-12: RTX 5090 Laptop GPU (24 GB, also driving the display), Ollama `0.40.3`,
`qwen3.8:27b` at a 64K window with a `q8_0` cache:

| Measure | Result |
|---------|--------|
| Placement | 100% GPU, 21.8 GB of VRAM in use at peak (about 1.2 GB of it the Windows desktop) |
| Cold start | ~17 s to load the model on the first request after the VRAM was given back |
| Prompt processing | 1,194 tokens/s (9,866 tokens in 8.3 s) |
| Generation | 27.9 tokens/s |
| Between turns | the prompt cache is reused; only new tokens are processed |
| End to end | a 9-turn edit-test-run task in 45 s |
| On the CPU instead | 55 s for a one-word reply |

An apply no longer loads the model, so the GPU stays free after one: the load happens on the first
request that needs it (a `claude-omni` session on this GPU starts its server on demand and lets
Ollama load the model), and `keepAlive` gives the VRAM back 15 minutes after the last request.

Through OmniRoute the cache is reused the same way: on 2026-10-15 an 11K-token prefix took 5.53 s
the first time and 1.15 s the second, against 5.50 s and 1.03 s sent to Ollama directly.

The GPU is shared with Windows. A game holding 10 GB of VRAM leaves too little for the model, and
Ollama then runs part of it on the CPU: the installer reports that as a warning, and `ollama ps`
shows the split.

## Another machine's GPU

Every machine with the model shares its server on the tailnet's port 11434, unless
`shareOnTailnet` says otherwise, and OmniRoute reaches it there as a provider of its own. Claude
Code itself still runs on the machine you work on: every file it reads or edits and every command
it runs stays there, and only inference happens on the other one.

1. Both machines are on the tailnet (see "Tailscale" in [CLAUDE.md](../CLAUDE.md)). A WSL machine
   is on it through Windows' Tailscale client, logged in once with its app; WSL reaches that
   client's CLI through the `tailscale` wrapper. A bare-metal machine runs `tailscaled`, which
   `chezmoi update` installs and logs in.
2. The share is `tailscale serve`, never Funnel; on WSL, Windows' client forwards to Windows'
   `localhost`, which WSL hands on to Ollama. Run `tailscale-up` in WSL once Windows is logged in.
   Docker Desktop uses `host.docker.internal` to reach Ollama directly, without Tailscale.
3. OmniRoute's provider for that machine points at its tailnet address -- the `100.x` one, which
   OmniRoute counts as private and gives five minutes to start answering; a MagicDNS name gets
   thirty seconds, too little for a cold model load. See [OmniRoute for Claude Code](omniroute-local.md).

Before a session on the other machine's GPU, `claude-omni` loads the model there and reads back
how the server holds it:

- **A different context window stops the launch.** The other machine renders its window from its
  own checkout, which may be older or carry a per-device override, and would truncate the prompt
  where Claude Code expects to compact it. Run `chezmoi update` there.
- **A model partly on the CPU only warns.** A GPU busy with a game leaves part of the model on
  that machine's CPU, where every request still succeeds, many times slower.

**A WSL machine serves only while its WSL runs**, and Windows stops WSL a few seconds after the
last WSL terminal closes. To use a desktop's GPU from the laptop, open a WSL terminal on the
desktop (RustDesk will do) and leave it open: Ollama starts with it. The desktop stays on the
tailnet meanwhile, because the client is Windows'; `tailscale set --unattended=true` there keeps
it on after its user signs out, and before the first sign-in after a reboot.

The other machine's GPU has the same 24 GB as this one, so it runs the same model, not a bigger
one: it is a second worker, useful while this GPU is busy, on battery, or already serving a run.

## Troubleshooting

- **Where does the model run?** `ollama ps`: the `PROCESSOR` column must read `100% GPU`.
- **Ollama found no GPU.** `journalctl --user -u ollama | grep 'inference compute'` should show
  `library=CUDA`. A `GPU discovery` failure with `signal: bus error` means a damaged install: a
  WSL VM that went down shortly after an install once left the two `libcublasLt` libraries
  truncated under a marker that said the install was complete, and CUDA discovery then crashed on
  every start while Ollama quietly served from the CPU. The installer now writes the marker only
  after the files are on disk, re-verifies every file against a digest manifest whenever it runs,
  and reinstalls when one no longer matches. It also makes this same check itself, against the log
  lines of the run it just restarted: only `library=cpu` there fails the apply. To run it now:
  `chezmoi execute-template < "$(chezmoi source-path)/.chezmoiscripts/run_onchange_after_linux-009-setup-ollama.sh.tmpl" | bash`
- **The server is not running.** `claude-omni` starts the user unit on demand when a session picks
  this machine's GPU; otherwise `systemctl --user status ollama`. When systemd itself is not
  running, `claude-omni` says so, and `systemctl` fails with `Failed to connect to user scope bus via
  local transport`: on WSL, `chezmoi apply` turns systemd on in `/etc/wsl.conf`, then
  `wsl.exe --shutdown` and a second apply start it and finish the setup, model download included.

## References

- [Ollama: Anthropic API compatibility](https://docs.ollama.com/api/anthropic-compatibility)
- [Ollama: context length](https://docs.ollama.com/context-length)
- [Tailscale: `tailscale serve`](https://tailscale.com/docs/reference/tailscale-cli/serve)
- [Tailscale: Windows with WSL 2](https://tailscale.com/kb/1295/install-windows-wsl2)
- [Tailscale: why resolv.conf gets overwritten](https://tailscale.com/docs/reference/faq/dns-resolv-conf)
