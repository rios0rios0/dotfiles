# Home-Secrets Backups

`~/.john`, `~/.sqlmap` and `~/.kube` (`config` and `config-files`) stopped syncing through chezmoi
in [#276](https://github.com/rios0rios0/dotfiles/pull/276): they are security-tool state and cluster
config, not good to commit to a dotfiles repository, and the inotify folder watcher that used to
archive them into the chezmoi source was flaky. `secrets-backup` backs them up off the machine
instead — one age-encrypted archive per run, kept on the machine and copied to the personal
OneDrive — as a smaller twin of the OmniRoute backups (`.docs/omniroute-local.md`).

It is **WSL only**: the personal OneDrive is reachable only from WSL, and the units and scripts are
gated accordingly in `.chezmoiignore`.

## What it does

`secrets-backup` (the systemd user timer `secrets-backup.timer` runs it daily at 03:45):

1. Packs the folders `.chezmoidata/secrets-backup.yaml` names (`secretsBackup.sources`) that exist
   under `$HOME` into a tar, keeping their permissions (a `~/.kube/config` comes back mode `600`).
   Only `.kube/config` and `.kube/config-files` are named, not `.kube` whole, so the regenerable
   discovery caches (`~/.kube/cache`, `~/.kube/http-cache`) stay out.
2. Encrypts the tar with the age identity at `~/.ssh/secrets-backup-key` to
   `~/.local/share/secrets-backups/secrets-<UTC>.tar.age`, keeping the newest `keep` (14).
3. Verifies the archive decrypts and that every entry belongs to a source, then copies it to
   `%OneDriveConsumer%\Backup\secrets\<deviceName>\`, keeping the newest `mirrorKeep` there plus the
   newest of each of the `mirrorMonthly` most recent months.

A missing identity fails the run (silently not backing up is worse); a mirror that cannot be written
fails it after the archive is kept locally; a run with none of the sources present is a no-op.

Run it by hand any time: `secrets-backup` (or `secrets-backup --help`).

## Restore

`secrets-restore` is the counterpart. On a machine that has only the backup key:

```bash
secrets-restore --list                 # newest first, from here and the mirror
secrets-restore                         # restore this device's newest archive
secrets-restore --device mxhero-z790    # restore another device's newest, from the mirror
secrets-restore --force                 # overwrite a source whose folder already exists
secrets-restore /path/to/secrets-….tar.age
```

It writes nothing until the archive passes its checks: it must decrypt with the key, and every tar
entry must belong to a configured source and escape nothing (no absolute path, no `..`). The age
recipient is public, so a planted archive is possible — that allowlist is what refuses one. A source
whose folder already exists is left alone unless `--force`, so a restore never silently clobbers
live state.

## The sync

`secrets-sync` (`.docs/secrets-sync.md`) keeps `~/.kube/config-files`, `~/.john/john.pot` and
`~/.sqlmap/output` the same on every WSL device, through `Backup\sync` in the same OneDrive and with
the same key. These backups stay underneath it, per device: a sync copies mistakes too, and the dated
archives are the way back. On a device that syncs, the next sync merges what a restore put back:
newer copies on the other devices win, and the restored versions they replace are kept in
`~/.local/state/secrets-sync/conflicts/`.

## The key

The backups, and the sync's snapshots, are encrypted to a dedicated age key — never the chezmoi
identity, nor the OmniRoute one — so no key's loss or rotation strands another's archives:

- on disk: `~/.ssh/secrets-backup-key`
- in 1Password: `op://Private/secrets-backup.age/private key` (public recipient in
  `.chezmoidata/age-keys.yaml`)

`chezmoi apply` fetches it from 1Password on every apply where it is missing or differs
(`run_before_linux-005-export-private-key.sh.tmpl`). **A lost key means lost backups**, so never
generate a new one in its place — it would decrypt none of the archives already taken.

To rotate it, follow "Rotating a key" in CLAUDE.md's "Age Keys" section (new `age-keygen` identity,
new `secrets-backup.age` item, its recipient in `age-keys.yaml`), then re-encrypt the archives still
worth keeping through `age -d -i <old> | age -e -a -r <new>`.

## Settings

`.chezmoidata/secrets-backup.yaml`:

| Key | Meaning |
|-----|---------|
| `sources` | home-relative paths to back up; each archived only when it exists |
| `keep` | how many archives stay on the machine |
| `mirror` | `'onedrive-personal'`, an absolute path, or `''` for no copy off the machine |
| `mirrorKeep` | how many of the newest stay in the mirror |
| `mirrorMonthly` | how many months keep their newest archive in the mirror |

An edit reaches the next apply without `chezmoi init` (chezmoi reads `.chezmoidata` every apply).

## Removing the feature

Add `path:` tombstones for `~/.local/bin/secrets-backup` and `~/.local/bin/secrets-restore` and
`~/.local/share/secrets-backups`, `.chezmoiremove` entries for
`~/.config/systemd/user/secrets-backup.{service,timer}`, disable the user timer, and drop the
`secretsBackup` key from `age-keys.yaml` and the export script. The deployed folders themselves
(`~/.john`, `~/.sqlmap`, `~/.kube`) are the user's and are left in place.
