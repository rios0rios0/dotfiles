# rclone OneDrive Setup Guide

A guide for configuring rclone with Microsoft OneDrive on Termux (Android).

## Why rclone?

On Termux, rclone is the best option for cloud storage sync:

- Available via `apt install rclone` (no manual builds)
- Native OneDrive support with OAuth authentication
- Supports copy, sync, move, and ls operations
- Scriptable for automated backups

Alternatives like the dedicated `onedrive` CLI (D-lang) are impractical to build on Termux, and `termux-share` only handles one file at a time.

## Initial Setup

### 1. Start the configuration wizard

```bash
rclone config
```

### 2. Walk through the prompts

| Prompt | Answer |
|--------|--------|
| `e/n/d/r/c/s/q>` | `n` (new remote) |
| `name>` | `onedrive` |
| `Storage>` | `onedrive` (or type the number next to "Microsoft OneDrive") |
| `client_id>` | Press Enter (leave blank) |
| `client_secret>` | Press Enter (leave blank) |
| `region>` | `1` (Microsoft Cloud Global) |
| `Edit advanced config?` | `n` |
| `Use web browser to automatically authenticate?` | `n` (Termux cannot auto-launch a browser; copy the URL and open it manually or use `termux-open-url <url>`) |

### 3. Authenticate via browser

rclone prints a URL like:

```
If your browser doesn't open automatically go to the following link: https://login.microsoftonline.com/common/oauth2/v2.0/authorize?...
```

**Important:** Open this URL in an **incognito/private browser tab** on your phone. This prevents the login page from auto-selecting a cached work/school account when you want to use a personal Microsoft account.

1. Sign in with your Microsoft account
2. Grant the requested permissions
3. The browser redirects to `localhost` with a token -- copy the **entire URL** from the address bar
4. Paste it back into the Termux prompt

### 4. Choose drive type

| Prompt | Answer |
|--------|--------|
| `config_type>` | `1` (OneDrive Personal or Business) |
| `config_driveid>` | Press Enter (accepts the detected drive) |
| `Is this okay?` | `y` |
| `e/n/d/r/c/s/q>` | `q` (quit config) |

### 5. Verify

```bash
rclone lsd onedrive:      # list top-level folders
rclone about onedrive:    # show storage usage
```

## Common Commands

### List files and directories

```bash
rclone lsd onedrive:              # list top-level directories
rclone ls onedrive:Documents/     # list all files in Documents recursively
rclone lsl onedrive:Documents/    # list with sizes and timestamps
```

### Upload files

```bash
# copy a single file
rclone copy ~/file.pdf onedrive:Documents/

# copy an entire directory (creates it if it doesn't exist)
rclone copy ~/Pictures onedrive:Pictures/

# copy with progress bar
rclone copy ~/backup onedrive:Backups/ --progress
```

### Sync a directory

```bash
# make remote match local (deletes remote files not present locally)
rclone sync ~/Documents onedrive:Documents/ --progress

# dry run first to see what would change
rclone sync ~/Documents onedrive:Documents/ --dry-run
```

### Download files

```bash
rclone copy onedrive:Documents/report.pdf ~/Downloads/
```

### Other operations

```bash
rclone mkdir onedrive:NewFolder           # create a directory
rclone delete onedrive:OldFolder/         # delete files (not directories)
rclone purge onedrive:OldFolder/          # delete directory and all contents
rclone move ~/file.txt onedrive:Documents/ # move (deletes local after upload)
```

## Tips

- **Bandwidth limit:** use `--bwlimit 1M` to cap upload speed (useful on mobile data)
- **Exclude patterns:** use `--exclude "*.tmp"` to skip files
- **Config location:** rclone stores its config at `~/.config/rclone/rclone.conf`
- **Token refresh:** rclone automatically refreshes the OAuth token; re-auth is only needed if the token is revoked or expires after prolonged inactivity
- **Multiple remotes:** run `rclone config` again to add Google Drive, S3, or other providers alongside OneDrive
