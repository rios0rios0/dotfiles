# Shell History with Atuin

Every interactive zsh, on WSL, bare-metal Linux and Termux, records its commands with
[Atuin](https://atuin.sh), which syncs them between devices through a server of our own on the
tailnet. Each client encrypts its history with a key that never leaves the devices, so the server
stores ciphertext. Ctrl-R and the up arrow open Atuin's search, and zsh-autosuggestions suggests
from it.

It replaces zsh-histdb, whose database this repository used to carry as encrypted files. Nothing
ever committed them, so they stopped at March 2025, and whole-file copies could not have merged
two devices' history anyway.

## How it fits together

| Part | Where |
|------|-------|
| Settings: the server's device, how others reach it, the port | `.chezmoidata/atuin.yaml`, read through `.chezmoitemplates/lib-atuin.tmpl` |
| Client | `atuin` `18.24.2`: `install_atuin` in the Linux installer (pinned, SHA-256 checked) and Termux's `atuin` package |
| Client settings | `~/.config/atuin/config.toml`, from `dot_config/atuin/config.toml.tmpl` |
| Client data | `~/.atuin/data/`: the history (`history.db`), the key (`key`) and the session (`meta.db`) |
| Shell | `.zshrc` runs `atuin init zsh --disable-ai` after Oh My Zsh |
| Server | `local-services/atuin/compose.yaml`, in Docker on the server's device, with SQLite in a volume |
| On the tailnet | that device's `tailscale-up` shares port 8888 with `tailscale serve` |
| The account's secrets | the 1Password item `Atuin` in `Private`, fields `password` and `key` (`account:` in `.chezmoidata/atuin.yaml`) |
| Login, on every apply | `run_after_linux-016-login-atuin.sh.tmpl` and `run_after_android-009-login-atuin.sh.tmpl` |
| The old history, once | `run_after_linux-017-import-atuin-history.sh.tmpl` and `run_after_android-010-import-atuin-history.sh.tmpl` |

The server runs on the laptop, `alien-a51`. Its own client syncs on loopback; every other device
syncs with `http://alien-a51:8888`, a MagicDNS name that WSL resolves through Windows' Tailscale
client and Termux through the Tailscale app.

There is exactly one server: Atuin servers never sync with each other. Each device keeps recording
while the server is unreachable and catches up the next time both are online, so a device sees
another's latest commands only after both have been online at the same time as the server. Moving
the server to a machine that is always on is
[issue #272](https://github.com/rios0rios0/dotfiles/issues/272) (see "Moving the server").

## Setting it up

Do it in this order: the server first, then the account; after that, every other device needs
nothing but a `chezmoi apply` from a revision that has Atuin, which installs it, writes its
settings, switches zsh over, logs it in and imports its old history once.

### 1. The server, on `alien-a51`

Windows' Tailscale app has to be logged in. From a checkout of this repository, with registration
open for the next step:

```sh
cd ~/.local/share/chezmoi
ATUIN_OPEN_REGISTRATION=true docker compose -f local-services/atuin/compose.yaml up -d
```

`chezmoi apply` shares port 8888 on the tailnet through `tailscale-up`. Check both halves:

```sh
curl -fsS http://127.0.0.1:8888/healthz && echo
tailscale serve status            # lists tcp 8888 forwarding to localhost:8888
```

### 2. The account

By hand, once, on `alien-a51`, which logs in as it registers. The secrets go where every other
device's apply reads them: a login item named `Atuin` in the personal account's `Private` vault,
the password in its `password` field and the encryption key in a concealed field named `key`
(`account:` in `.chezmoidata/atuin.yaml` names the account, vault, item and username). Let
1Password generate the password, then hand it to Atuin in its environment, which it reads when no
`--password` is given, so it never reaches the screen or a command line:

```sh
ATUIN_PASSWORD="$(op read --account my 'op://Private/Atuin/password')" atuin register -u <username> -e <email>
atuin key                                 # the encryption key, for the item's `key` field
```

The key cannot be recovered, and every other device needs it. Then close registration:

```sh
docker compose -f local-services/atuin/compose.yaml up -d
```

### 3. The other devices

Nothing to do: every `chezmoi apply` logs in a device that is not logged in yet. A device that is
costs one `atuin status`, which reports the missing session from the local database before it
reaches the network. On Linux the login reads the item's two fields at run time through `op`; on
Termux, where no script can call `op`, chezmoi renders them into the script from its own 1Password
session, and only on an apply whose render finds no session. Either way the password reaches
`atuin login` in its environment and the key on its stdin. Anything that stops it -- no network,
1Password locked, the server down -- is an `[atuin] WARN:` line, and the next apply tries again.
The server's own device is only warned about: it registered in step 2.

By hand, on a device where the apply cannot reach 1Password:

```sh
op read --account my 'op://Private/Atuin/key' |
    ATUIN_PASSWORD="$(op read --account my 'op://Private/Atuin/password')" atuin login -u <username>
```

### 4. The old history, once per device

The apply after the login imports it: the commands zsh-histdb recorded under the device's own
hosts, taken from a private copy of `~/.histdb/zsh-history.db`, then a sync that uploads them. The
hosts are the device's hostname, both of the desktop's names (`devices.mxhero-z790.histdbHosts`
in `.chezmoidata/atuin.yaml`), and on Termux `localhost`, renamed to the device's name as the shell
now records it. It waits for the login, since only the sync after it uploads the imported commands.
Two markers in `~/.atuin/data/` make it once: `.dotfiles-histdb-imported` after the import, which
`atuin import` needs because it does not deduplicate, and `.dotfiles-histdb-synced` after the sync,
which every apply retries until it succeeds. A device that never ran zsh-histdb gets both markers
and imports nothing.

**A device imported by hand needs the first marker created by hand**, or its next apply imports
the same commands again: `touch ~/.atuin/data/.dotfiles-histdb-imported`. Its next apply then
syncs once and writes the second. `alien-a51` was imported by hand on 2026-10-28.

The commands below do it by hand. `atuin import` fills only the local database; the explicit
`atuin sync` after it is what adds the imported commands to the record store that sync sends, and
uploads them. Atuin's shell hook exports `ATUIN_SESSION`, which that sync needs: in a script or any
other non-interactive shell it fails with `Failed to find $ATUIN_SESSION in the environment` unless
it runs as `ATUIN_SESSION="$(atuin uuid)" atuin sync`.

**`mxhero-z790`**, the desktop, imports all of its history, under both of its names
(`rios0rios0-z790` until March 2025, `mxhero-z790` since):

```sh
atuin import zsh-hist-db
atuin sync
```

**`alien-a51`** imports only its own commands. Its database also holds the desktop's March 2025
snapshot, which this repository deployed there and which the desktop imports itself. `VACUUM INTO`
takes a consistent copy, including what is still in the write-ahead log:

```sh
sqlite3 ~/.histdb/zsh-history.db "VACUUM INTO '/tmp/histdb-own.db'"
sqlite3 /tmp/histdb-own.db "DELETE FROM history WHERE place_id IN (SELECT id FROM places WHERE host <> 'alien-a51')"
HISTDB_FILE=/tmp/histdb-own.db atuin import zsh-hist-db
rm /tmp/histdb-own.db
atuin sync
```

**Termux** recorded its commands under `localhost`; the copy names them after the device instead, as
the shell now records them (`ATUIN_HOST_NAME`):

```sh
sqlite3 ~/.histdb/zsh-history.db "VACUUM INTO '$TMPDIR/histdb-own.db'"
sqlite3 "$TMPDIR/histdb-own.db" "UPDATE places SET host = '$ATUIN_HOST_NAME' WHERE host = 'localhost'"
HISTDB_FILE="$TMPDIR/histdb-own.db" atuin import zsh-hist-db
rm "$TMPDIR/histdb-own.db"
atuin sync
```

If a duplicate slips in anyway, `atuin history dedup --dry-run --before <date> --dupkeep 1` lists
entries with the same command, directory and host, and the same command without `--dry-run`
deletes them. `~/.histdb` itself stays where it was, as a fallback; nothing reads it any more.

## Day to day

Nothing to do. After a command, Atuin syncs in the background once five minutes have passed since
the last sync. `atuin sync` syncs now, and `atuin status` shows the account and the last sync.

## What the server sees

The command, its directory, host, exit code and duration are encrypted on the device. The server
sees what each record carries in the clear: when the command ran, roughly how long its text is,
and a random ID per device. Deleting a command adds a deletion record and leaves the encrypted
original on the server, which only deleting the account removes. The key, `~/.atuin/data/key` on
each device and the `key` field of the 1Password item, is what protects all of it: anyone with the
key and a copy of the server's database can read everything ever synced.

Atuin refuses to record a command that carries a recognisable credential (`secrets_filter`). Add
patterns of your own with `history_filter` in `~/.config/atuin/config.toml`, through
`dot_config/atuin/config.toml.tmpl`. The client never asks `api.atuin.sh` for updates
(`update_check = false`), so it talks to nothing but the server.

## Moving the server

To an always-on machine, once there is one:

1. Start `local-services/atuin/compose.yaml` there with registration open, and register the same
   username.
2. Set `serverDevice`, and `serverHost` if its name does not resolve everywhere, in
   `.chezmoidata/atuin.yaml`, then `chezmoi apply` on every device.
3. On one device that is up to date, run `atuin login` against the new server with the same key,
   then `atuin store push`. It uploads every record it holds, from every device.
4. Close registration on the new server. On the old device, stop the container with
   `docker compose -f local-services/atuin/compose.yaml down`, and drop its tailnet share with
   `tailscale serve --tcp=8888 off`: a `serve` entry outlives the configuration that set it.

## Troubleshooting

| Symptom | Check |
|---------|-------|
| `atuin sync` cannot connect from another device | The laptop is on and Docker Desktop runs there, which starts the container by itself (`restart: always`): `docker compose -f local-services/atuin/compose.yaml ps`. Then `tailscale serve status` on the laptop |
| The name `alien-a51` does not resolve on a device | Give that device the laptop's tailnet address: `tailscale ip -4 alien-a51`, as `devices.<deviceName>.serverHost` in `.chezmoidata/atuin.yaml` |
| `atuin register` fails with registration closed | Start the container with `ATUIN_OPEN_REGISTRATION=true`, as in step 1 |
| A device is still not logged in after an apply | The apply's `[atuin] WARN:` line says why; `atuin status` says whether a session exists, and step 3 has the login by hand |
| `atuin sync` fails with `Failed to find $ATUIN_SESSION in the environment` | It ran outside an interactive zsh: `ATUIN_SESSION="$(atuin uuid)" atuin sync` |
| Ctrl-R opens Oh My Zsh's search, not Atuin's | `atuin` is not on `PATH` in that shell: `command -v atuin`; on Linux the dependency installer installs it into `~/.local/bin` |
| Anything else | `atuin doctor` |
