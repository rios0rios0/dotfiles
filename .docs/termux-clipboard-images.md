# Clipboard Images on Termux: Making Claude Code's Ctrl+V Work

On Termux, pressing Ctrl+V in Claude Code to attach a screenshot always failed with
`No image found in clipboard`. This document records how the cause was found, why every
off-the-shelf fix is a dead end on Android, and how the shim that solves it is built.

The short version: Claude Code has no native clipboard binding. It shells out to `xclip`.
Anything on `PATH` named `xclip` that answers two invocations is a clipboard as far as it
is concerned, so the fix is a shim rather than a port.

## The Problem

Three separate things have to be true for a clipboard image to reach Claude Code, and on
Android none of them are.

| Layer | Status on Termux |
|-------|------------------|
| A clipboard that can hold a bitmap | Android's clipboard holds a `content://` URI, not pixels, and another app's sandbox cannot resolve it without an explicit grant |
| A display server owning a selection | Termux has no `DISPLAY` and no `WAYLAND_DISPLAY` |
| A tool that reads that selection | `xclip` and `wl-paste` are not packaged for Termux, and would have nothing to read if they were |

Android screenshots are written to a file. The `Copy` button in the screenshot editor puts
a URI on the clipboard, not the image, so even a working clipboard bridge would hand over a
string that Termux cannot dereference.

## Discovery

The Claude Code binary is a Bun-compiled executable. The clipboard contract was read
straight out of it:

```bash
BIN=~/.local/share/claude/versions/<version>/claude
grep -a -b -o -F -e 'checkImage:' -e '.saveImage' "$BIN"
tail -c +<offset> "$BIN" | head -c 4200 | tr -c '[:print:]' '.'
```

That yields the command table. On Linux, with the WSL-only PowerShell fallbacks empty:

```sh
# checkImage
xclip -selection clipboard -t TARGETS -o 2>/dev/null | grep -E "image/(png|jpeg|jpg|gif|webp|bmp)" \
  || wl-paste -l 2>/dev/null | grep -E "image/(png|jpeg|jpg|gif|webp|bmp)"

# saveImage  (target path is $TMPDIR/claude_cli_latest_screenshot.png)
xclip -selection clipboard -t image/png -o > "$TMP" 2>/dev/null \
  || wl-paste --type image/png > "$TMP" 2>/dev/null \
  || xclip -selection clipboard -t image/bmp -o > "$TMP" 2>/dev/null \
  || wl-paste --type image/bmp > "$TMP"

# deleteFile
rm -f -- "$TMP"
```

Four properties of that table are what make a shim viable, and each was verified on a device:

| Property | Consequence |
|----------|-------------|
| The commands are strings run with `shell: true`, so `xclip` is resolved by `PATH` inside `/bin/sh` | A script in `~/.local/bin` intercepts them. Android's `/bin/sh` exists (it is `mksh`), and `~/.local/bin` is on the `PATH` Claude Code inherits from its wrapper |
| The read path has **no** `DISPLAY` gate | The gate found in the source sits in `probe()`, which selects a tool for the *copy* direction only. Paste calls `checkImage` unconditionally |
| Success is decided by the pipeline's exit status | `grep` only has to match one line of the shim's output. No X11 protocol is involved anywhere |
| After reading the file, Claude Code sniffs magic bytes and derives the media type from them | The `.png` in the temp path is a name, not a requirement. The JPEG that Android actually writes is passed through untouched, so the shim needs no image conversion and no dependency on ImageMagick |

The commands are also rebuilt on every paste, so dropping the shim onto `PATH` takes effect
in an already-running session without a restart.

## Alternatives Considered

### termux-x11 — rejected: solves the wrong half

Running an X server would give a real `xclip` a display to talk to, and it would work in the
sense that `xclip` would stop erroring. It still would not see a screenshot: an X selection is
owned by X clients, and the Android screenshot service is not one. Copying an image into that
selection would first require the bridge that does not exist.

### Termux:API — rejected for images, kept for text

`termux-clipboard-get` calls `ClipboardManager` and returns `getText()`. There is no image
variant, and adding one would run into the URI permission problem above. It is still worth
having for the *text* leg, so the shim routes text targets to it when present. It needs both
the `termux-api` package and the companion app.

### Typing the file path — works, but is not the feature

Naming the file in the prompt has always worked, and the paste handler also accepts a pasted
*path* ending in `.png`, `.jpg`, `.gif` or `.webp`. Neither is Ctrl+V, and both mean leaving
the keyboard mid-thought to go find a filename.

## The Shim

`dot_local/bin/executable_xclip` answers the two invocations and synthesises the clipboard
from the filesystem. `dot_local/bin/executable_clipshot` stages an arbitrary image for the
same path. `dot_local/lib/claude-clipboard.sh` holds what both need, and is the only place
the watched folders are declared. All three are Android-only, via `.chezmoiignore`.

That last file is not incidental. The shim decides what Ctrl+V attaches, and `clipshot -s`
exists to report what the shim would pick, so two copies of the folder list would let them
disagree on the same device and turn the diagnostic into a second source of confusion. A
device whose captures land in `~/storage/pictures/Screenshot` rather than the plural variant
is exactly where that bites, and it is the case a duplicated list is most likely to miss.

The image served is resolved in this order:

1. `$CLAUDE_CLIPBOARD_IMAGE`, when set and readable
2. a file staged by `clipshot`
3. the newest image across the watched folders, if it is fresh enough

| Decision | Why |
|----------|-----|
| Default source is the newest screenshot in `~/storage/{pictures,dcim}/Screenshots` and `~/storage/downloads` | "Take a screenshot, then Ctrl+V" is the entire feature. Anything requiring an app switch or a typed path is what this replaces |
| It must be younger than `CLAUDE_CLIPBOARD_MAX_AGE` (default `600` seconds) | Without a window, a Ctrl+V days later silently attaches whatever was last captured, which is worse than failing |
| An image is marked consumed once its bytes are read | Makes it behave like a clipboard instead of a sticky file, and lets a second Ctrl+V fall through to text. `CLAUDE_CLIPBOARD_REPEAT=1` opts out |
| Consumption happens on `saveImage`, never on `checkImage` | Claude Code always calls the check first. Consuming there would make the very next call fail and attach nothing |
| Raw bytes are passed even when the requested target is `image/png` | Magic-byte sniffing happens downstream, so a conversion step would add a dependency and buy nothing |
| Unknown arguments exit non-zero and silently | The shim is not an `xclip` implementation. Anything it does not recognise should look like an empty clipboard, not an error |

`clipshot` covers what the freshness window deliberately excludes:

```bash
clipshot                 # stage the newest image, whatever its age
clipshot <file>          # stage a specific image
clipshot -s              # show what Ctrl+V would attach right now
clipshot -c              # clear staged image and consumed marker
```

State lives in `${XDG_CACHE_HOME:-$HOME/.cache}/claude-clipboard/`.

## Verifying

Run the literal commands Claude Code issues, rather than the shim's own interface, so the
test exercises the real contract:

```bash
rm -f ~/.cache/claude-clipboard/consumed
TMP=$TMPDIR/claude_cli_latest_screenshot.png

/bin/sh -c 'xclip -selection clipboard -t TARGETS -o 2>/dev/null \
  | grep -E "image/(png|jpeg|jpg|gif|webp|bmp)"'          # expect: image/png, exit 0

/bin/sh -c "xclip -selection clipboard -t image/png -o > $TMP 2>/dev/null"
file "$TMP"                                               # expect: PNG or JPEG image data

/bin/sh -c 'xclip -selection clipboard -t TARGETS -o 2>/dev/null \
  | grep -E "image/(png|jpeg)"'                           # expect: exit 1, consumed
```

Point `CLAUDE_CLIPBOARD_DIRS` at a scratch directory to test the freshness window without
touching the gallery.

`make test-clipboard-shim` does all of that in CI, against a scratch directory and a 1x1 PNG
fixture, and `CLAUDE_CLIPBOARD_LIB` lets it point the scripts at the repository's copy of the
library rather than an installed one. The suite covers both directions of the freshness
window, the consumed marker, the `checkImage`-must-not-consume ordering, the override
precedence, and the agreement between `clipshot -s` and the shim.

## Troubleshooting

| Symptom | Check |
|---------|-------|
| Ctrl+V still reports an empty clipboard | `clipshot -s`. If `newest` is `none`, storage permission was never granted: run `termux-setup-storage` |
| A screenshot is listed but not attached | It is older than `CLAUDE_CLIPBOARD_MAX_AGE`, or already consumed. `clipshot` stages it regardless |
| The wrong image is attached | A stale staged file. `clipshot -c` clears it |
| Text paste stopped working | An image is being offered ahead of it. `clipshot -c`, and confirm `termux-clipboard-get` exists for the text leg to work at all |

## References

- `CLAUDE.md`, section "Clipboard Images on Termux (Ctrl+V)" for the condensed version
- `dot_local/bin/executable_xclip`, `dot_local/bin/executable_clipshot`, `dot_local/lib/claude-clipboard.sh`
- `.github/ci/scripts/test-clipboard-shim.sh`, run by `make test-clipboard-shim`
- [Termux:API clipboard documentation](https://wiki.termux.com/wiki/Termux:API)
