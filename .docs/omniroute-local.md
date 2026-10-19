# OmniRoute for Claude Code

OmniRoute is a local gateway that routes each Claude Code request to the provider behind its model id:
this machine's or another machine's Ollama, NVIDIA NIM, OpenRouter, Baseten. `claude-omni` starts Claude
Code through it. Its Compose stack and local environment files live in `local-services/omniroute/` and
run from the dotfiles checkout; chezmoi deploys none of it. The dashboard and API run locally, with Redis
available only on the internal Docker network. Compose keeps the existing `dotfiles` project name so
moving the files does not switch to new named data volumes. OpenCode V2 is the gateway's second
client: see [OpenCode V2 through OmniRoute](opencode-local.md).

## Start OmniRoute

Run these commands from `local-services/omniroute/`. Copy the environment template and restrict its permissions:

```bash
cp .env.example .env
chmod 600 .env
```

Generate and set four values in `.env`:

| Variable | Generate with | Purpose |
|----------|---------------|---------|
| `JWT_SECRET` | `openssl rand -base64 48` | Signs dashboard sessions |
| `API_KEY_SECRET` | `openssl rand -hex 32` | Encrypts provider API keys |
| `INITIAL_PASSWORD` | `openssl rand -hex 24` | First dashboard login password |
| `STORAGE_ENCRYPTION_KEY` | `openssl rand -hex 32` | Encrypts the local database |

Keep these values private and preserve them across restarts. Changing the encryption keys can make stored data or provider credentials unreadable.

Start the services and open the dashboard:

```bash
docker compose up -d
docker compose logs -f omniroute
```

Open `http://127.0.0.1:20128`. The initial dashboard setup may ask for a bootstrap token; find it in the `omniroute` service logs. Create a dashboard API key for Claude Code after signing in.

The Compose file pins a custom build of the fork (`ghcr.io/rios0rios0/omniroute`) by digest rather than the official image; see [The custom fork image](#the-custom-fork-image). Both services use `restart: always`, so Docker starts them automatically when its daemon starts. All published ports bind to `127.0.0.1`; Redis has no host-published port. `docker compose down` preserves the named data volumes. `docker compose down -v` deletes the database, Redis data, and configured provider credentials.

## The custom fork image

The stack runs `ghcr.io/rios0rios0/omniroute`, built from the `feat/model-quota-api` branch of the [`rios0rios0/OmniRoute`](https://github.com/rios0rios0/OmniRoute) fork, because the gateway needs that branch's model-scoped quota endpoint. The official `diegosouzapw/omniroute` image does not carry it.

The [publish workflow](https://github.com/rios0rios0/OmniRoute/blob/feat/model-quota-api/.github/workflows/publish-ghcr.yml) builds and pushes the image on every push to that branch. It uses the Dockerfile's `runner-base` target for `linux/amd64` -- the same flavour as the official image the stack ran before, without Chromium/Playwright, so the web-cookie providers (`gemini-web`, `claude-web`, `claude-turnstile`) are unavailable. Hosted builds take 27-55 minutes and use `OMNIROUTE_USE_TURBOPACK=0` with a 12 GB heap, the settings upstream's publish workflow validated.

The fork keeps only that workflow enabled: the inherited upstream workflows (CI, CodeQL, semgrep, Publish to npm, Deploy to VPS, the nightly suite, and the rest) are disabled in its Actions settings, so a matching branch or PR cannot start a job that would fail for lack of secrets. Re-enable one deliberately before using it.

Each build publishes two tags: `:feat-model-quota-api`, which moves with the branch, and `:sha-<full commit>`, which does not. The Compose file pins the **digest**, never the branch tag: a tag cannot name the code a running container holds.

### Update the pin

Push the branch and wait for **Publish custom image to GHCR** to finish. Then, from `local-services/omniroute/`:

```bash
./update-image.sh
docker compose pull omniroute
docker compose up -d omniroute
```

`update-image.sh` asks GitHub for the newest successful run of the workflow, resolves the digest of that commit's `sha-<commit>` tag, and rewrites the `omniroute` image line in `compose.yaml`; it prints the two commands above. `--check` exits 1 when the pin is not the newest build, `--tag TAG` pins a release tag instead, and `--file PATH` rewrites another Compose file. It needs `gh` authenticated to the fork and `docker` with buildx; a public package resolves anonymously, a private one needs `docker login ghcr.io` first. A failed or unfinished build leaves the previous pin in place.

The pin is recognized by the repository's final path component and in either quoting style, so the official image of the first run, this fork's, and a mirror named by `OMNIROUTE_IMAGE` are all readable — a pin an earlier run wrote stays updatable. The rewrite keeps the quoting the file already used and is read back with the same matcher before it replaces the file, so a writer and a reader that disagree fail the run instead of producing a file the next one cannot parse.

### Data, migrations and rollback

The Compose project keeps its name (`dotfiles`) and volume names (`omniroute-data`, `omniroute-redis-data`), so switching the image reuses the existing database and provider credentials. The fork is based on upstream `v3.8.52`, whose migrations run on the first start and are one-way: take a backup before recreating the container.

```bash
omniroute-backup
docker compose up -d omniroute
```

Rolling the image reference back is not enough once migrations have run; restore the database and `server.env` from the backup (see [Encrypted backups](#encrypted-backups)). Keep both the previous digest from `git diff` and the archive taken just before the switch.

### Package visibility

The fork repository is public, so the GHCR package is public and Compose pulls it without credentials. If the package is made private, run `docker login ghcr.io` with a token carrying `read:packages` before `docker compose pull`; otherwise the pull fails while the last pulled image keeps running.

## Connect the GPUs' Ollama

OmniRoute runs in a Docker container while Ollama runs directly in WSL, on this machine and on any other
GPU machine on the tailnet. Each GPU is an Ollama provider of its own in OmniRoute's **Providers** page,
and its prefix must match a key of `gpus` in `.chezmoidata/omniroute.yaml`, which is how `claude-omni`
knows a model runs on a GPU and which one:

| Prefix | Base URL | Where |
|--------|----------|-------|
| `ollama-laptop` | `http://host.docker.internal:11434` | this machine |
| `ollama-desktop` | `http://<the other machine's 100.x address>:11434` | another machine on the tailnet; `tailscale ip -4 <name>` prints the address |

Docker Desktop provides `host.docker.internal` for containers to reach host services. Ollama
listens on IPv4 loopback (`127.0.0.1:11434`): the container dials Windows' IPv4 loopback, and WSL's
localhost relay puts an IPv4 listener exactly there — with `0.0.0.0` the listener is a dual-stack
`[::]` that Windows sees on `::1` alone, and the container's fetch fails with `ECONNREFUSED` while
the server is up. Tailscale Serve forwards the tailnet's port to this same `localhost:11434`. No
extra proxy, `socat`, or systemd bridge is needed. The API has no authentication, and loopback
keeps the network off it directly.

The dotfiles checkout is shared by two machines, so the local/remote roles come from chezmoi's
`deviceName`, not from a machine guess at runtime. On the laptop (`alien-a51`), `ollama-laptop` is
local and `ollama-desktop` is the desktop. On the desktop (`mxhero-z790`), a per-device override
swaps those roles: `ollama-desktop` is local and `ollama-laptop` is the laptop. Check the value on
each machine with `chezmoi data | jq -r .deviceName`; `CHEZMOI_DEVICE` can override the hostname
when set before `chezmoi init`.

Do not add a `host-gateway` mapping: with Docker Desktop it points at the Docker VM's bridge rather
than the Windows host. Container traffic to the remote GPU leaves through Windows and traverses its
Tailscale client. Use the remote machine's `100.x` address rather than a MagicDNS name: OmniRoute
counts that range as private and gives such a host five minutes to start answering, enough for a cold
model load, where a name gets thirty seconds.

Give each Ollama model a manual context window of `contextTokens` from `.chezmoidata/local-llm.yaml`
(65536). OmniRoute cannot see the window an Ollama server allocates and assumes its 128000 fallback;
with the override, it rejects an oversized request instead of letting Ollama truncate it.
`claude-omni` declares the same window itself, so the override is the second guard.

**Known limitation: the tailnet GPU answers 403.** `tailscale-up` shares the server with
`tailscale serve --tcp=11434`, a raw TCP forward, so a request from another machine keeps its own
`Host: 100.x:11434` header all the way to Ollama, which refuses a host it does not serve with HTTP
403. The provider is configured and its port is reachable, yet every request through OmniRoute
fails. Reproduce on the machine that owns the GPU:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: 100.70.110.25:11434' http://127.0.0.1:11434/api/version
# 403
```

The local GPU is unaffected: Docker reaches it through `host.docker.internal`, which Ollama accepts.
Until the forward is changed to rewrite the header -- an HTTPS-mode `tailscale serve` proxy rather
than a TCP forward -- use the local GPU or a cloud model.

### Fix Redis snapshot permission errors

If Redis logs `Failed opening the temp RDB file ... /data ... Permission denied`, recreate Redis after updating the Compose file. Do not override Redis capabilities in Compose: the image needs `CHOWN`, `SETUID` and `SETGID` to repair the data volume ownership, then drop to its unprivileged user before starting the server.

```bash
docker compose up -d --force-recreate redis
docker compose logs --tail=50 redis
```

This recreates only the Redis container and keeps the named Redis data volume.

## Fix provider TLS validation

If NVIDIA NIM or OpenRouter reports `SELF_SIGNED_CERT_IN_CHAIN` or `fetch failed` while validating a key, the request is reaching a TLS certificate authority that the container does not trust. This is a certificate trust problem, not evidence that the API key is invalid. The Compose service adds the host CA bundle to Node.js trust through a read-only mount. On Linux, it defaults to `/etc/ssl/certs/ca-certificates.crt`.

If you use Windows with WSL and the CA is trusted only by Windows, open `certmgr.msc` (current-user store) or `certlm.msc` (local-machine store). Under **Trusted Root Certification Authorities > Certificates**, export the network's trusted root CA as **Base-64 encoded X.509 (.CER)** and choose not to export a private key. Copy the certificate into a WSL path readable by the container process, then set `OMNIROUTE_CA_BUNDLE` in `local-services/omniroute/.env` to that absolute path. The variable can also point to a PEM bundle containing multiple trusted certificates. Only add a CA you trust.

Recreate OmniRoute so Docker applies the new mount and environment setting, then retry provider validation:

```bash
docker compose up -d --force-recreate omniroute
```

Do not disable TLS certificate verification to work around this error.

## Add the cloud providers

In the dashboard, open **Providers**, connect NVIDIA NIM, OpenRouter and Baseten, and add their API keys.
Test each connection, then enable the providers and models you want the router to consider.

**NVIDIA NIM lists models this account cannot use.** OmniRoute's built-in NIM list is stale. On
2026-10-15, one tool-call request to each of its 55 chat models came back as:

| Result | Models |
|--------|--------|
| HTTP 404 from NIM | 39 (among them `moonshotai/kimi-k2.6`, `mistralai/mistral-large`, `mistralai/codestral-22b-instruct-v0.1`, `meta/llama2-70b`) |
| HTTP 500 or no answer | 2 (one 500, one timeout) |
| Answered without calling the tool | 1 |
| Called the tool | 13; the fast ones, under 6 s: `z-ai/glm-5.3`, `nvidia/nemotron-3-super-120b-a12b`, `openai/gpt-oss-20b`, `stepfun-ai/step-5-preview` |

Following that probe, OmniRoute hides 68 of its 81 NIM chat entries; the 13 that called the tool in
the latest probe remain visible. Three models that were visible after an older probe were hidden
because they were not confirmed by this run: one was absent from the current catalog, one timed out,
and one returned HTTP 500. This visibility is stored in OmniRoute's database, not in this checkout,
and it is the whole of the curation: `claude-omni` lists what `/v1/models` serves, so a model hidden
here is absent from its picker too. `claude-omni --probe nvidia/` repeats the probe; each request may
incur provider charges. OmniRoute reports no authoritative NIM context window, so the picker shows `?`
rather than presenting its generic 128000 fallback as fact.

**Why the first answer can take a minute.** NIM queues requests: `z-ai/glm-5.3-flash` started answering
after 30-35 seconds. OmniRoute aborted that first attempt at its 30-second default and retried on a
fresh socket, which queued it again: 61-65 seconds in all. The Compose file raises
`OMNIROUTE_DIRECT_HEADERS_TIMEOUT_MS` to two minutes, so a queued request is waited for once. OmniRoute
lifts the bound to three minutes by itself only for requests that ask for high effort.

## Claude Code through OmniRoute (`claude-omni`)

Create an API key for Claude Code in the dashboard, and put it in this device's 1Password note as a
concealed field labelled `cred:OMNIROUTE_API_KEY`. `reload-credentials` (or a new shell) exports it as
`OMNIROUTE_API_KEY`. `claude-omni` hands it to Claude Code for that one process only, so the regular
`claude`, its claude.ai login and ccswitch's rotation are untouched.

```bash
claude-omni                                    # pick a model; each line shows its context window
claude-omni -m nvidia/z-ai/glm-5.3             # straight in
claude-omni -m ollama-desktop/qwen3.8:27b -p "add a test for Subtract"   # print mode, like `claude -p`
claude-omni -c -m openrouter/z-ai/glm-5.3      # switch model, keeping the conversation
claude-omni --list                             # the models OmniRoute serves, their windows and where they run
claude-omni --list --all                       # every chat model OmniRoute serves, with its window
claude-omni --probe nvidia/                    # which models under a prefix answer with a tool call
```

The picker is the gateway's own catalog: every launch reads OmniRoute's `/v1/models` and lists the
chat models that can call tools, the GPUs' own model leading and each line showing its context
window. No model list lives in this repository, so a model is added, hidden or restricted in
OmniRoute's dashboard and the picker follows -- `efforts` in `.chezmoidata/omniroute.yaml` is the
one per-model setting kept here (a Claude Code effort level, low to xhigh). Enter takes the model
the profile saved last; if that one is no longer served, the first served one starts. Without a
terminal -- in print mode, or from a script -- it takes that model without asking. The first launch
shows Claude Code's onboarding once, because the session runs in its own profile (`~/.claude-omni`),
and its trust prompt once per project. `chezmoi apply` keeps the regular profile's theme, renderer
and status line there; see "Claude Code and Codex Look" in
[CLAUDE.md](../CLAUDE.md).

### The window a session gets

Claude Code reads no context window from a gateway: it assumes 200K for a model id it does not
recognise, and takes one `CLAUDE_CODE_MAX_CONTEXT_TOKENS` for the whole process. `claude-omni` sets it to
the smaller of OmniRoute's window, which OmniRoute enforces, and this repository's:

| Model | Window | `--list` shows |
|-------|--------|----------------|
| On a GPU | `contextTokens` from `local-llm.yaml`, what the server allocates | `64K` |
| One OmniRoute knows (its catalog has `max_input_tokens`) | OmniRoute's | `256K` |
| One OmniRoute does not know (no `max_input_tokens`) | OmniRoute's 128000 fallback, with a warning | `128K?` |
| An `auto/*` combo | `autoWindow` (200000); OmniRoute advertises the largest window in the pool | `200K` |

The reply reservation follows the window: an eighth of it, between 8,192 and 32,000 tokens.

Every Claude Code tier -- Opus, Sonnet, Haiku, Fable and subagents -- is pinned to the one model, and
`CLAUDE_CODE_DISABLE_1M_CONTEXT=1` keeps `/model`'s Default row from turning the model id into
`<id>[1m]`, which Claude Code would size at 1,000,000 tokens.

### Switching models

In the session, `/model` lists the models OmniRoute serves whose window is at least the session's,
each with its window and provider. The window stays the session's after a switch, so a model with a
smaller one would overflow before the session compacts, and OmniRoute's answer to an over-window
request is not one Claude Code compacts on. `claude-omni -c -m ID` reaches any model, and keeps the
conversation.

The status line shows the model and the session's window, `ctx 80% left (13k/64k)`. After a switch it adds
the new model's own window, `(13k/64k · model 256k)`, and turns red when that one is smaller, which can
only happen with a model id typed into `/model` by hand.

### The profile

`~/.claude-omni` is a profile of its own: `/model` choices are saved to its settings, and in the regular
profile they would be sent to Anthropic. It also leaves out the regular profile's plugins, skills, agents
and MCP servers. Two files the launcher writes sit there as well: `omniroute-settings.json`, named on
Claude Code's command line because the `/model` lineup outgrows a command-line argument, and
`omniroute-windows.tsv`, every served model's window for the status line.

On a window of 128K or less the session is also lean, because what loads before the first prompt has to
fit. Measured with `/context` on 2026-10-12 (Claude Code `2.1.296`):

| Profile | dotfiles repository | ccswitch repository |
|---------|--------------------|---------------------|
| Regular profile | 72.8K tokens | 50.7K tokens |
| Lean profile, at a 64K window | 37.2K tokens, 7.1K free | 18.5K tokens, **25.9K free** |

- **Tool schemas.** For a model it does not recognise, Claude Code sends every tool schema with every
  request instead of deferring the rarely used ones: 27K tokens. `--tools` limits a lean session to six
  (5.8K).
- **Global rules.** A separate `CLAUDE_CONFIG_DIR` does not drop `~/.claude/rules`: for any project under
  `$HOME`, Claude Code reads that directory as the rules of the ancestor directory `~`.
  `claudeMdExcludes` keeps only the rules `lean.rules` lists.
- **The reply reservation.** Claude Code reserves room for a reply plus about 13K before it
  auto-compacts; an eighth of a 64K window leaves 21.2K of it for that.

A repository whose own `CLAUDE.md` is as large as this one's (26.9K tokens) leaves too little room for a
64K window and is better served by a larger model.

### Delegating a task (`claude-omni-task`)

An agent that hands a task to another model -- `omniroute-general` in the
[aifiles](https://github.com/rios0rios0/aifiles) agents -- runs it through `claude-omni-task`:

```bash
claude-omni-task brief.md                              # the first free GPU in taskGpus
claude-omni-task -m nvidia/z-ai/glm-5.3 brief.md       # a model named by the caller
```

Without `-m` it tries `taskGpus` in order and takes the first GPU that no other run holds (a lock per
GPU, since a GPU serves one request at a time) and that passes the launch checks. A cloud model runs only
when named, and then every file the model reads goes to that provider; the audit says so. The model runs
unattended with every permission check off, as the caller's own session does. Nobody watches it, so
instead of restricting it, `claude-omni-task` returns all of it to the caller:

- **every action**, in order, with its result: each command and its output, each file read or
  written, a write outside the repository flagged as one;
- **the change**, measured between snapshots of the working tree taken before and after the run,
  untracked files included. The snapshots go through a scratch copy of the index, so the
  caller's own index is never touched, and edits that were already in the tree are never
  attributed to the run;
- **one command that undoes exactly that change** (`git diff --binary <before> <after> | git
  apply -R`), and one that shows it;
- **the transcript**, which Claude Code keeps under `~/.claude-omni/projects`.

It prints the audit in short and saves it in full under `~/.claude-omni/audits`. What an audit cannot
take back is whatever left the working tree -- a commit, a push, a request to a server, a write
somewhere else. Those show up in the action list and as a moved HEAD, and nowhere else.

## Encrypted backups

The stack's state lives in a Docker volume, where `docker compose down -v`, a corrupted volume or a
lost machine takes it with them. `omniroute-backup` writes a daily, age-encrypted snapshot of it:

- **What**: a consistent copy of `storage.sqlite`, taken with `VACUUM INTO` inside the running
  container -- copying a live WAL database file can tear it -- plus the `server.env` the bootstrap
  wrote, with the storage-key version it records. Call logs are not included.
- **Where**: `~/.local/share/omniroute-backups/`, the newest 14 kept; `OMNIROUTE_BACKUP_DIR`,
  `OMNIROUTE_BACKUP_KEEP` and `OMNIROUTE_CONTAINER` adjust that in the environment.
- **How**: the tar is encrypted with the age identity at `~/.ssh/omniroute-backup-key`, a key of
  its own -- never the chezmoi one -- so neither key's loss or rotation touches the other. **Keep a
  copy of it off this machine: without it every backup is unreadable.** A systemd user timer
  (`omniroute-backup.timer`, enabled by `chezmoi apply` on WSL) runs it daily at 03:30, or at the
  next boot when 03:30 was missed; run `omniroute-backup` by hand after any doubt.

To restore, pick the archive and unpack it; a restore rolls the database back to that snapshot,
API keys, settings and usage included:

```bash
mkdir -p /tmp/omniroute-restore
age -d -i ~/.ssh/omniroute-backup-key ~/.local/share/omniroute-backups/omniroute-<stamp>.tar.age \
    | tar -x -C /tmp/omniroute-restore
cd local-services/omniroute
docker compose stop omniroute
docker run --rm -v dotfiles_omniroute-data:/data -v /tmp/omniroute-restore:/restore alpine sh -c \
    'rm -f /data/storage.sqlite /data/storage.sqlite-wal /data/storage.sqlite-shm &&
     cp /restore/storage.sqlite /restore/server.env /data/ &&
     chown 1000:1000 /data/storage.sqlite /data/server.env &&
     chmod 600 /data/storage.sqlite /data/server.env'
docker compose start omniroute
```

The helper container writes into the named volume while the stack is stopped: `docker cp` cannot
remove the stale `-wal`/`-shm` files beside a replaced database, and a database that mounts next to
a stale write-ahead log is not the one that was backed up. `make test-omniroute-backup` covers the
script, its retention and the installer's gate.

## Privacy boundary

The dashboard, routing API, provider credentials and database remain on this machine. Prompts sent to NVIDIA, OpenRouter or Baseten still leave the machine and are handled under that provider's own retention and usage policies; in a Claude Code session, the prompt includes every file the model reads. Use only providers and models whose data terms fit the work you send. The GPU models never leave your own machines.

## References

- [Claude Code: gateway compatibility guide](https://code.claude.com/docs/en/llm-gateway-protocol)
- [Claude Code: correct the window for a gateway or custom model ID](https://code.claude.com/docs/en/model-config#correct-the-window-for-a-gateway-or-custom-model-id)
- [Claude Code: environment variables](https://code.claude.com/docs/en/env-vars)
- [Claude Code: `modelPicker`](https://code.claude.com/docs/en/settings-reference#modelpicker)
- [OmniRoute](https://github.com/diegosouzapw/OmniRoute)
