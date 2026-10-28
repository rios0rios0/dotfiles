# The OmniRoute Gateway

OmniRoute is a local gateway that routes each request to the provider behind its model id: this
machine's or another machine's Ollama, NVIDIA NIM, OpenRouter, Baseten. OpenCode -- on Linux `ocode`,
the fork build -- is its client: see [OpenCode V2 through OmniRoute](opencode-local.md). Its Compose
stack and local environment files live in `local-services/omniroute/` and run from the dotfiles
checkout; chezmoi deploys none of it. The dashboard and API run locally, with Redis available only on
the internal Docker network. Compose keeps the existing `dotfiles` project name so moving the files
does not switch to new named data volumes.

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
| `API_KEY_SECRET` | `openssl rand -hex 32` | Signs the check digits of the `sk-…` API keys the dashboard creates |
| `INITIAL_PASSWORD` | `openssl rand -hex 24` | First dashboard login password |
| `STORAGE_ENCRYPTION_KEY` | `openssl rand -hex 32` | Encrypts the provider credentials (API keys, OAuth tokens) stored in the database; the database file itself is plain SQLite |

Keep these values private and preserve them across restarts. A different `STORAGE_ENCRYPTION_KEY` leaves every stored provider credential unreadable: the gateway still starts, and every cloud provider fails. Keep a copy of the finished `.env` in 1Password -- the `OmniRouter` item in `Private`, with the file `OMNIROUTE_CA_BUNDLE` names attached as `ca-bundle.pem` -- which is where `omniroute-restore` looks when neither the checkout nor the archive has one (`env:` in `.chezmoidata/omniroute.yaml`).

Start the services and open the dashboard:

```bash
docker compose up -d
docker compose logs -f omniroute
```

Open `http://127.0.0.1:20128`. The initial dashboard setup may ask for a bootstrap token; find it in the `omniroute` service logs. Create an API key for OpenCode after signing in; see [Connect OpenCode](#connect-opencode).

The Compose file pins a custom build of the fork (`ghcr.io/rios0rios0/omniroute`) by digest rather than the official image; see [The custom fork image](#the-custom-fork-image). Both services use `restart: always`, so Docker starts them automatically when its daemon starts. All published ports bind to `127.0.0.1`; Redis has no host-published port. `docker compose down` preserves the named data volumes. `docker compose down -v` deletes the database, Redis data, and configured provider credentials.

This first `docker compose up` is the only start that creates a database. From then on, every `chezmoi apply` on WSL keeps the stack running (`run_after_linux-015-start-omniroute.sh.tmpl`): it starts a stack whose data volume exists but whose containers do not, leaves a running or stopped container alone, and only prints what to do -- restore an archive, or run that first `up` -- when there is no data volume. Docker starts the stack only when Docker Desktop runs, so turn on **Start Docker Desktop when you sign in to your computer** in Docker Desktop's **Settings > General**; while it is off, the gateway stays down after every reboot, and the apply says so when it finds Docker down.

## The custom fork image

The stack runs `ghcr.io/rios0rios0/omniroute`, built from the `reworked` branch of the [`rios0rios0/OmniRoute`](https://github.com/rios0rios0/OmniRoute) fork, because the gateway needs that branch's model-scoped quota endpoint. The official `diegosouzapw/omniroute` image does not carry it.

The [publish workflow](https://github.com/rios0rios0/OmniRoute/blob/reworked/.github/workflows/publish-ghcr.yml) builds and pushes the image on every push to that branch. It uses the Dockerfile's `runner-base` target for `linux/amd64` -- the same flavour as the official image the stack ran before, without Chromium/Playwright, so the web-cookie providers (`gemini-web`, `claude-web`, `claude-turnstile`) are unavailable. Hosted builds take 27-55 minutes and use `OMNIROUTE_USE_TURBOPACK=0` with a 12 GB heap, the settings upstream's publish workflow validated.

The fork keeps only that workflow enabled: the inherited upstream workflows (CI, CodeQL, semgrep, Publish to npm, Deploy to VPS, the nightly suite, and the rest) are disabled in its Actions settings, so a matching branch or PR cannot start a job that would fail for lack of secrets. Re-enable one deliberately before using it.

Each build publishes two tags: `:reworked`, which moves with the branch, and `:sha-<full commit>`, which does not. The Compose file pins the **digest**, never the branch tag: a tag cannot name the code a running container holds.

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

Rolling the image reference back is not enough once migrations have run; put the previous digest back and restore the archive taken just before the switch with `omniroute-restore` (see [Restore](#restore)). Keep both the previous digest from `git diff` and that archive.

### Package visibility

The fork repository is public, so the GHCR package is public and Compose pulls it without credentials. If the package is made private, run `docker login ghcr.io` with a token carrying `read:packages` before `docker compose pull`; otherwise the pull fails while the last pulled image keeps running.

A stale login breaks even the public pull. Docker sends the `ghcr.io` login `~/.docker/config.json` keeps with every pull from it, and GHCR answers an expired token with `denied`, whatever the package's visibility; `omniroute-restore` and the start on apply say so instead of `offline?`. On these machines that file is rendered from the device note's `docker:` lines, so remove the line, or renew the token behind it (a classic token: GitHub Packages accepts no fine-grained one), and apply again. For a single pull, `DOCKER_CONFIG="$(mktemp -d)" docker pull <image>` goes without any login.

## Connect the GPUs' Ollama

OmniRoute runs in a Docker container while Ollama runs directly in WSL, on this machine and on any other
GPU machine on the tailnet. Each GPU is an Ollama provider of its own in OmniRoute's **Providers** page,
and its model ids carry that provider's prefix:

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

The table is the laptop's (`alien-a51`) view. On the desktop (`mxhero-z790`) the roles swap:
`ollama-desktop` is local, at `host.docker.internal`, and `ollama-laptop` is the laptop's tailnet
address. Each machine's providers live in its own OmniRoute database, not in this checkout.

Do not add a `host-gateway` mapping: with Docker Desktop it points at the Docker VM's bridge rather
than the Windows host. Container traffic to the remote GPU leaves through Windows and traverses its
Tailscale client. Use the remote machine's `100.x` address rather than a MagicDNS name: OmniRoute
counts that range as private and gives such a host five minutes to start answering, enough for a cold
model load, where a name gets thirty seconds.

Give each Ollama model a manual context window of `contextTokens` from `.chezmoidata/local-llm.yaml`
(65536). OmniRoute cannot see the window an Ollama server allocates and assumes its 128000 fallback;
with the override, it rejects an oversized request instead of letting Ollama truncate it.

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
and it is the whole of the curation: OpenCode lists what `/v1/models` serves, so a model hidden
there is absent from its picker too. OmniRoute reports no authoritative context window for NIM
models; the 128000 it gives them is its generic fallback.

**Why the first answer can take a minute.** NIM queues requests: `z-ai/glm-5.3-flash` started answering
after 30-35 seconds. OmniRoute aborted that first attempt at its 30-second default and retried on a
fresh socket, which queued it again: 61-65 seconds in all. The Compose file raises
`OMNIROUTE_DIRECT_HEADERS_TIMEOUT_MS` to two minutes, so a queued request is waited for once. OmniRoute
lifts the bound to three minutes by itself only for requests that ask for high effort.

## Connect OpenCode

Create an API key for OpenCode in the dashboard, and put it in this device's 1Password note as a
concealed field labelled `cred:OMNIROUTE_API_KEY`. `reload-credentials` (or a new shell) exports it as
`OMNIROUTE_API_KEY`, which OpenCode reads when it loads its configuration; the key never enters this
repository. That configuration points OpenCode's provider at `baseUrl` in
`.chezmoidata/omniroute.yaml` (`http://127.0.0.1:20128`), the one OmniRoute setting kept here, and
the models it offers are whatever the key's policy lets `/v1/models` serve: a model is added, hidden
or restricted in OmniRoute's dashboard, and OpenCode follows. Setup and usage are in
[OpenCode V2 through OmniRoute](opencode-local.md).

The Compose file sets `OMNIROUTE_DISABLE_THINKING_LEVEL_VARIANTS`, so `/v1/models` lists a reasoning
model once instead of adding a `<model>-<tier>` row per effort tier; OpenCode offers the tiers as the
model's variants instead. The flag is a feature flag, and a value set in the dashboard (Settings,
Feature Flags) overrides the Compose one: if the suffixed rows come back, look there for an override
before suspecting the image.

## Encrypted backups

The stack's state lives in a Docker volume, where `docker compose down -v`, a corrupted volume or a
lost machine takes it with them. `omniroute-backup` writes a daily, age-encrypted archive of it that
restores the gateway on its own, and copies it off the machine:

- **What**: a consistent copy of `storage.sqlite`, taken with `VACUUM INTO` inside the running
  container -- copying a live WAL database file can tear it -- the `server.env` the bootstrap wrote;
  `compose.env`, the secrets `.env` gave the gateway, without which the stored provider credentials
  never decrypt again; a `manifest` naming the device, the image, the schema and how many providers
  and API keys the database holds; and the CA bundle `OMNIROUTE_CA_BUNDLE` names, when it names one
  of its own. Call logs and Redis are not included.
- **Where**: `~/.local/share/omniroute-backups/`, the newest 14 kept, and a copy in the personal
  OneDrive -- the folder Windows names in `%OneDriveConsumer%`, never `%OneDrive%`, which on a
  machine also signed in to a work account is that one -- under
  `Backup\omniroute\<deviceName>\`, where the newest 14 stay plus the newest of each of the last 12
  months. `backup:` in `.chezmoidata/omniroute.yaml` sets those numbers and the mirror (an absolute
  path instead, or `''` for none); `OMNIROUTE_BACKUP_DIR`, `OMNIROUTE_BACKUP_KEEP`,
  `OMNIROUTE_BACKUP_MIRROR` and `OMNIROUTE_CONTAINER` override them in the environment. A mirror that
  cannot be written fails the run after the archive is kept here, so `systemctl --user --failed`
  shows it.
- **An empty gateway**: a database with no provider and no API key -- a freshly started stack -- is
  archived here, but rotates nothing out and is not copied, so it never pushes the real archives
  out of either place.
- **How**: the tar is encrypted with the age identity at `~/.ssh/omniroute-backup-key`, a key of
  its own -- never the chezmoi one -- so neither key's loss or rotation touches the other. Its copy
  off this machine is the `omniroute-backup.age` item in 1Password, which `chezmoi apply` writes
  back whenever the file is missing (see "Age Keys" in `CLAUDE.md`). **Without it every backup is
  unreadable, so never replace it with a newly generated key.** A systemd user timer
  (`omniroute-backup.timer`, enabled by `chezmoi apply` on WSL) runs it daily at 03:30, or at the
  next boot when 03:30 was missed; run `omniroute-backup` by hand after any doubt.

### Restore

`omniroute-restore` brings an archive back, rolling the database to that snapshot -- API keys,
settings and usage included -- and is safe on a fresh machine that has nothing but the backup key:

```bash
omniroute-restore --list                       # this device's archives, here and in the mirror
omniroute-restore                              # the newest of them
omniroute-restore --device mxhero-z790         # the newest archive another device mirrored
omniroute-restore ~/Downloads/omniroute-<stamp>.tar.age
```

Before it changes anything, it checks that the archive holds only what `omniroute-backup` writes,
that the database passes SQLite's integrity check, that the image `compose.yaml` pins knows the
database's schema (migrations only go forward: pin a newer image first otherwise), and that the key
the gateway will start with decrypts a stored credential. It shows what it found and asks; `--yes`
answers for it. Then it snapshots a running stack with `omniroute-backup` and stops it, writes the
database into the volume as the container's user, starts the stack, waits for it to be healthy and
takes the first backup. It never runs `docker compose down -v`, and Redis keeps its volume: it holds
only counters and caches.

`.env` is never generated: the checkout's own stays, a missing one comes from the archive's
`compose.env`, and an archive from before that member gets the copy in 1Password -- whose note may
keep it in a Markdown code block: the fence lines are dropped. The CA bundle
`.env` names comes from the archive or 1Password the same way, written where `.env` says when that is
under your home directory. `omniroute-restore --env-only` does only that, without touching Docker --
what `chezmoi apply` suggests on a machine with no `.env`. When the checkout's `.env` does not open the
archive's credentials, the restore stops: move that `.env` aside to use the archive's, or pass
`--allow-key-mismatch` and enter the provider keys again in the dashboard afterwards.

Restoring another device's archive makes that database this machine's: its next backups go to this
device's folder. The Ollama provider addresses and API keys are the other device's, so check them in
the dashboard, and that `cred:OMNIROUTE_API_KEY` on this device's 1Password note is a key the restored
database knows. `make test-omniroute-backup`, `make test-omniroute-restore` and
`make test-omniroute-stack` cover the archive and its mirror, the restore, and the start on apply.

### Recover from an old Docker Desktop disk

With no archive anywhere but the old Windows installation's disk still at hand -- after a reinstall,
say -- the database can come out of Docker Desktop's own data disk, as it did on `alien-a51` on
2026-10-28. The old disk is only ever read; everything else works on a copy, in a folder private to
you, since it holds the database and `server.env`.

1. Attach the old disk so that it gets a drive letter (unlock it first if BitLocker protects it). Docker
   Desktop's data disk is `<drive>:\Users\<user>\AppData\Local\Docker\wsl\disk\docker_data.vhdx`
   (`wsl\data\ext4.vhdx` in older versions); the small `wsl\main\ext4.vhdx` beside it holds no volumes.
2. Copy it with a Windows tool, from a Windows directory (WSL sees a drive attached after it started
   only after a restart):

   ```bash
   cd /mnt/c && robocopy.exe '<drive>:\Users\<user>\AppData\Local\Docker\wsl\disk' 'D:\recovery' docker_data.vhdx /J
   ```

3. Install `qemu-img` (`sudo apt install qemu-utils`). A disk Docker never detached cleanly still
   holds a VHDX journal, which has to be replayed -- on the copy, since that writes -- before anything
   reads it. Then convert it to a raw image on WSL's own disk, where it stays sparse: on a Windows
   drive it would be written out to its whole virtual size, up to 1 TiB.

   ```bash
   mkdir -m 700 ~/recovery
   qemu-img check -r all /mnt/d/recovery/docker_data.vhdx
   qemu-img convert -f vhdx -O raw /mnt/d/recovery/docker_data.vhdx ~/recovery/docker_data.raw
   ```

4. Copy the volume's files out with `debugfs` in read-only mode, mounting nothing. The write-ahead
   log comes too: it holds the last writes, which an unclean stop leaves outside the database file.
   `db_backups/` in the same folder keeps OmniRoute's own pre-migration snapshots, as a fallback.

   ```bash
   volume=/data/docker/volumes/dotfiles_omniroute-data/_data
   for name in storage.sqlite storage.sqlite-wal server.env; do
       debugfs -c -R "dump $volume/$name $HOME/recovery/$name" ~/recovery/docker_data.raw
   done
   ```

5. Fold the log into one consistent file -- opening the database with its `-wal` beside it applies the
   log -- and check it:

   ```bash
   sqlite3 ~/recovery/storage.sqlite "VACUUM INTO '$HOME/recovery/snapshot.sqlite'"
   sqlite3 ~/recovery/snapshot.sqlite 'PRAGMA integrity_check;'
   ```

6. Pack the snapshot and `server.env` as an archive from before the manifest, encrypted with the
   backup key, and restore it. With no `compose.env` in it, `.env` comes from 1Password, and every
   check above runs before the volume is touched:

   ```bash
   mkdir -m 700 ~/recovery/stage
   cp ~/recovery/snapshot.sqlite ~/recovery/stage/storage.sqlite
   cp ~/recovery/server.env ~/recovery/stage/
   tar -C ~/recovery/stage -cf - storage.sqlite server.env |
       age -e -i ~/.ssh/omniroute-backup-key -o ~/recovery/omniroute-recovered.tar.age
   omniroute-restore ~/recovery/omniroute-recovered.tar.age
   ```

The restore takes a backup as soon as the stack is healthy and mirrors it, so delete the copies
afterwards: `D:\recovery`, `~/recovery`, and `qemu-utils` if nothing else needs it. WSL's own disk
does not give the space back to Windows while WSL runs.

## Privacy boundary

The dashboard, routing API, provider credentials and database remain on this machine. Prompts sent to NVIDIA, OpenRouter or Baseten still leave the machine and are handled under that provider's own retention and usage policies; in an OpenCode session, the prompt includes every file the model reads. Use only providers and models whose data terms fit the work you send. The GPU models never leave your own machines.

## References

- [OmniRoute](https://github.com/diegosouzapw/OmniRoute)
- [OpenCode V2 through OmniRoute](opencode-local.md)
