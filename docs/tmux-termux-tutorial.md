# Beginner's Guide: tmux on Termux (Android)

A practical tutorial for using tmux on a touchscreen with Termux's limited keyboard.

## Why tmux on Termux?

1. **Phantom Process Killer** — Android 12+ kills apps with more than ~32 child processes. tmux consolidates everything under one process tree, keeping you under the limit.
2. **Session persistence** — if Termux is backgrounded or accidentally closed, tmux sessions survive (as long as the process isn't killed).
3. **Split screen** — run multiple terminals side by side without opening multiple Termux tabs.

## Your Keyboard: Termux Extra-Keys

Termux provides two rows of extra keys above the regular keyboard:

```
┌─────┬───┬───┬──────┬────┬─────┬──────┐
│ ESC │ / │ - │ HOME │ UP │ END │ PGUP │
├─────┼───┴───┼──────┼────┼─────┼──────┤
│ TAB │ CTRL  │SHIFT │LEFT│DOWN │RIGHT │ PGDN │
└─────┴───────┴──────┴────┴─────┴──────┘
```

Keys you'll use constantly with tmux:
- **CTRL** — needed for the prefix (`Ctrl+a`)
- **Arrow keys** (UP/DOWN/LEFT/RIGHT) — navigate between panes, scroll in copy mode
- **ESC** — exit copy/scroll mode
- **`-`** — split panes horizontally (custom binding)
- **PGUP/PGDN** — scroll through output in copy mode

## The Prefix: How tmux Commands Work

Almost every tmux command starts with a **prefix** — a key combination that tells tmux "the next key is a command, not regular typing."

This config uses **`Ctrl+a`** as the prefix (the default `Ctrl+b` is harder to reach on mobile).

**How to type it:**
1. Tap **CTRL** on the extra-keys row (it stays held)
2. Tap **`a`** on the regular keyboard
3. Release — you're now in command mode for the next keypress
4. Tap the **command key** (e.g., `c` to create a window)

> Throughout this guide, `prefix` means `Ctrl+a`.

## Getting Started

### Start tmux

```bash
tmux                    # start a new session
tmux new -s work        # start a named session called "work"
```

### Detach and Reattach

| Action | How |
|--------|-----|
| Detach (leave session running) | `prefix` then `d` |
| List sessions | `tmux ls` |
| Reattach to last session | `tmux attach` |
| Reattach to named session | `tmux attach -t work` |

### Kill Everything

```bash
tmux kill-server        # destroy all sessions
```

## Windows (Like Browser Tabs)

Windows are full-screen terminals within a session. The status bar at the bottom shows all windows.

| Action | Keys |
|--------|------|
| Create new window | `prefix` then `c` |
| Next window | `prefix` then `n` |
| Previous window | `prefix` then `p` |
| List all windows (interactive) | `prefix` then `w` |
| Go to window 1, 2, 3... | `prefix` then `1`, `2`, `3`... |
| Rename current window | `prefix` then `,` |
| Close window | Type `exit` or press `Ctrl+d` |

## Panes (Split Screen)

Panes divide a window into multiple terminals. This is where tmux shines on mobile — you can see logs in one pane while typing commands in another.

### Splitting

| Action | Keys | Note |
|--------|------|------|
| Split horizontally (top/bottom) | `prefix` then `-` | `-` is on the extra-keys row |
| Split vertically (left/right) | `prefix` then `\|` | requires SHIFT for the pipe character |

### Navigating

**Option A — Keyboard:**

`prefix` then arrow keys (UP/DOWN/LEFT/RIGHT are all on the extra-keys row).

**Option B — Touch (recommended):**

Just **tap the pane** you want to focus. Mouse mode is enabled by default.

### Resizing

**Touch:** Drag the border between panes.

**Keyboard:** `prefix` then hold `Ctrl` and press arrow keys repeatedly.

### Other Pane Operations

| Action | Keys |
|--------|------|
| Zoom pane (toggle fullscreen) | `prefix` then `z` |
| Close pane | Type `exit` or press `Ctrl+d` |
| Swap with previous pane | `prefix` then `{` |
| Swap with next pane | `prefix` then `}` |

> **Tip:** Zoom (`prefix` + `z`) is your best friend on a small screen. Expand a pane to full screen, do your work, then zoom out again.

## Scrolling and Copy Mode

By default, you can't scroll up to see previous output. You need **copy mode**.

| Action | How |
|--------|-----|
| Enter copy mode | `prefix` then `[` — or **swipe up** (mouse mode) |
| Scroll | Arrow keys, PGUP/PGDN (all on extra-keys) |
| Exit copy mode | `q` or **ESC** (on extra-keys) |

## Quick Reference Card

| Action | Keys | Extra-Keys Used |
|--------|------|-----------------|
| Prefix | `Ctrl+a` | CTRL |
| Detach | `prefix` + `d` | CTRL |
| New window | `prefix` + `c` | CTRL |
| Next window | `prefix` + `n` | CTRL |
| Previous window | `prefix` + `p` | CTRL |
| Split horizontal | `prefix` + `-` | CTRL, `-` |
| Split vertical | `prefix` + `\|` | CTRL |
| Navigate panes | `prefix` + arrows | CTRL, arrows |
| Navigate panes (touch) | Tap the pane | — |
| Zoom pane | `prefix` + `z` | CTRL |
| Copy/scroll mode | `prefix` + `[` | CTRL |
| Exit copy mode | `q` or ESC | ESC |
| Resize pane (touch) | Drag border | — |
| Reload config | `prefix` + `r` | CTRL |

## Tips for Mobile

1. **Use mouse mode** — tapping panes is much faster than keyboard navigation on a touchscreen.
2. **Landscape mode** — rotate your phone when using split panes. Portrait is too narrow for side-by-side.
3. **Zoom is your friend** — `prefix` + `z` to toggle a pane between fullscreen and split. Work zoomed in, zoom out to check the other pane.
4. **Named sessions** — use `tmux new -s name` so you can easily reattach later (`tmux attach -t name`).
5. **One session, multiple windows** — prefer windows over tabs. Windows are managed inside tmux and won't trigger the Phantom Process Killer.
6. **Pinch to zoom** — Termux supports pinch-to-zoom for font size. Useful when panes get small.
7. **`tmux kill-server`** — when things get messy, clean up all sessions and start fresh.

## Common Workflows

### Running Claude Code with logs visible

```bash
tmux new -s dev           # start a session
# ... Claude Code runs here ...
prefix + -                # split horizontally
tail -f ~/.claude/logs/*  # watch logs in the bottom pane
# tap the top pane to go back to Claude Code
```

### Multiple projects

```bash
tmux new -s project-a     # first project
# ... work on project A ...
prefix + d                # detach

tmux new -s project-b     # second project
# ... work on project B ...
prefix + d                # detach

tmux ls                   # see both sessions
tmux attach -t project-a  # jump back to A
```
