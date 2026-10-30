# Home-Secrets Sync

`secrets-backup` keeps each device's history of `~/.kube`, `~/.john` and `~/.sqlmap`
(`.docs/secrets-backup.md`). `secrets-sync` keeps the devices themselves in step. Every WSL device
that has a tool's folder shares one copy of it, merged through the personal OneDrive, and a delete on
one device reaches the others. There is no server: OneDrive is the only thing in between, and each
device does its own merging.

It is **WSL only**, like the backups: the personal OneDrive is reachable only from WSL.

## What syncs, and how

`.chezmoidata/secrets-sync.yaml` names the tools:

| Tool | What | Merge | Stays on each device |
|------|------|-------|----------------------|
| `kube` | `~/.kube/config-files/*`, one kubeconfig per cluster | `entries`: each file is one entry, and the newest wins | each file's `current-context` line, and `~/.kube/config` itself |
| `john` | `~/.john/john.pot`, John the Ripper's cracked hashes | `lines`: every device's lines join | `john.log` and the session files (`*.rec`) |
| `sqlmap` | `~/.sqlmap/output/*`, one folder per target | `entries`: each target folder is one entry, and the newest wins | everything else under `~/.sqlmap` |

A tool syncs on a device that has its folder (`~/.kube`, `~/.john`, `~/.sqlmap`), so a machine that
never ran John never gets a `~/.john`.

**Why the `current-context` stays behind.** With several kubeconfigs in `KUBECONFIG`,
`kubectl config use-context` writes the new context into the first file that already has one. The
shell's loader (`linux-engineering-detect-kube-config-files.sh`) lists `~/.kube/config-files` first,
so that file is one of the synced ones. If those lines synced, switching to production on the laptop
would switch the desktop's next `kubectl apply` to production too. The sync leaves them out of every
comparison and every snapshot, and keeps a device's own line when a newer copy of the file arrives.

**Why `~/.kube/config` stays behind.** Its contexts (Docker Desktop, kind) point at the machine's own
loopback and mean nothing on another one. The backups keep it.

## How a merge decides

Each run, for each tool:

1. **It reads this device's folder and its base**, the state this device last synced
   (`~/.local/state/secrets-sync/<tool>/base`). An entry that differs from the base is a change. An
   entry in the base that is gone from the folder is a delete.
2. **It reads every device's snapshot** from the hub (`<hub>/<tool>/<device>.tar.age`), its own
   included, and checks each one's MAC.
3. **The newest record wins for each entry.** A change is dated by the file's modification time. A
   delete is dated just after this device last synced, so it beats every copy that existed then and
   loses to a change made since, which this device never saw.
4. **It applies the winners** to the folder, writes the new base, and publishes this device's
   snapshot. It publishes only when something changed, so an idle hour writes nothing to OneDrive.

**Joining.** A device without a base deletes nothing. Its files and the hub's are merged by
modification time. Two devices that each had files before their first sync end up with the union,
the newer copy of each file winning. A machine restored from an old archive takes the newer copies
rather than pushing its old ones out.

**Conflicts are kept, never dropped.** A local change that loses to a newer one from another
device is copied to `~/.local/state/secrets-sync/conflicts/<tool>/<time>/<name>` before it is
replaced. When two devices change the same entry between syncs, the device whose change wins also
keeps the other device's version, as `<name>.<device>`. Each run that keeps something says so with a
`WARN` line.

## Running it

The user timer `secrets-sync.timer` runs it hourly, and at once after a start that missed an hour.
To run it by hand:

```bash
secrets-sync                    # merge and publish now
secrets-sync --dry-run          # say what would change, and change nothing
secrets-sync --allow-deletes    # let a large delete through (see below)
journalctl --user -u secrets-sync   # what the timer's runs did
```

Each run ends with one line per tool, such as `kube: 25 entries, merged with mxhero-z790`, after a
line for everything it took or deleted.

## When it stops

| Message | Why | What to do |
|---------|-----|------------|
| `… is gone, though it held entries at the last sync` | the tool's folder vanished; the sync will not read that as deleting everything everywhere | put it back (`secrets-restore`), or run with `--allow-deletes` if it was meant |
| `this run would delete N of M entries, more than 50%` | this device deleted most of a tool | if it was meant, `secrets-sync --allow-deletes`; the other devices then apply the deletes without the flag |
| `… fails its authentication check` | a snapshot in the hub was not written by a device holding this key | delete that file from the hub; the rest of the sync still ran |
| `… is encrypted to another key` | a snapshot for another key is in the hub | the same |
| `the hub cannot be reached` | the personal OneDrive is not set up on this machine | sign in to OneDrive with the personal account |

A snapshot that cannot be read whole yet (still downloading, or offline) is skipped for that run
without failing it.

## Recovering

- **A change you wanted back** is in `~/.local/state/secrets-sync/conflicts/`, or in the daily
  backups (`secrets-restore --list`).
- **To make an older copy win**, put it in place and `touch` it, then sync. A copy restored with its
  old modification time loses to the newer one the other devices hold. That is what makes a restore
  on a new machine safe.
- **To rejoin a device from scratch**, delete its base (`~/.local/state/secrets-sync/<tool>`). The
  next run treats it as joining: it deletes nothing, and takes the newer copies.
- **After `secrets-restore --force`**, the next sync merges what it restored. Newer copies from the
  other devices win, and the restored versions they replace go to `conflicts/`.

## The hub and the key

The hub is `%OneDriveConsumer%\Backup\sync\<tool>\<device>.tar.age` (`hub: 'onedrive-personal'`),
never `%OneDrive%`, which on a machine signed in to a work account names that one. Each device writes
only its own file. OneDrive has no locking, so two devices rewriting one shared file would leave a
renamed copy behind: a silent fork.

A snapshot is an age-encrypted tar of a `manifest` and `data/`. The manifest lists each entry's
record (live with its SHA-256, or a delete) and ends in an HMAC-SHA256 keyed from the identity's
secret half. The sync uses the home-secrets backup key, `~/.ssh/secrets-backup-key`, for both: it
carries the same folders to the same devices and the same OneDrive. The age recipient is public
(`.chezmoidata/age-keys.yaml`), so anyone who can write to the OneDrive could encrypt a snapshot to it.
The MAC is what they cannot make, and a kubeconfig's `exec` plugin is code that `kubectl` runs. Every
entry taken from a snapshot is checked against its manifest's digest before it is written.

## What stays per device

- **`~/.kube/config`**, `john.log`, `*.rec` and the rest of `~/.sqlmap`, for the reasons above.
- **The OmniRoute database.** It is one gateway's state and cannot be merged: two devices'
  databases would only overwrite each other. Its backups stay per device, and
  `omniroute-restore --device <name>` moves the gateway to another machine
  (`.docs/omniroute-local.md`).

## Settings

`.chezmoidata/secrets-sync.yaml`:

| Key | Meaning |
|-----|---------|
| `hub` | `'onedrive-personal'`, an absolute path, or `''` to sync nothing |
| `tombstoneDays` | how long a delete is remembered; a device that has not synced for longer can bring back what was deleted meanwhile |
| `maxDeletePercent` | the share of a tool one run may delete before `--allow-deletes` is needed; a single delete always passes |
| `tools[].name` | the hub folder's name |
| `tools[].path` | the folder (`entries`) or file (`lines`) under `$HOME` |
| `tools[].merge` | `entries` or `lines` |
| `tools[].localLines` | `entries` only: an extended regular expression for the lines a file keeps to itself |

An edit reaches the next apply without `chezmoi init`. Every device must run the same settings.
A snapshot written for another merge is skipped.

## Removing the feature

Add `.chezmoiremove` entries for `~/.local/bin/secrets-sync` and
`~/.config/systemd/user/secrets-sync.{service,timer}`, disable the user timer, and delete
`~/.local/state/secrets-sync` (its `conflicts/` first, if anything there is worth keeping) and the
hub folder `Backup\sync` in the personal OneDrive. The synced folders themselves are the user's and
stay in place.
