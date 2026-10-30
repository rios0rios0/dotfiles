{{- /* The agent guide chezmoi writes to ~/AGENTS.md on every platform: what any agent should
     know about this machine before it runs a command. It is not the repository's AGENTS.md, which
     is for agents working on the dotfiles and is never deployed; see "The Home AGENTS.md" there.
     It is the only home-level instruction file: aisync's ~/.claude/CLAUDE.md and
     ~/.config/opencode/AGENTS.md are deleted, so what they carried lives here. Agents load it
     into their context -- OpenCode V2 and Claude Code both read every AGENTS.md from their working
     directory up to the home folder -- so keep it short, and true for the platform it is rendered
     for: every fact here was checked on that platform. */ -}}
{{- $os := .chezmoi.os -}}
{{- $wsl := and (eq $os "linux") (contains "microsoft" (.chezmoi.kernel | toString)) -}}
{{- $zsh := or (eq $os "linux") (eq $os "android") -}}
{{- $platform := $os -}}
{{- if $wsl }}{{ $platform = "Kali Linux on WSL 2" }}{{ else if eq $os "linux" }}{{ $platform = "Linux" }}{{ else if eq $os "android" }}{{ $platform = "Termux on Android" }}{{ else if eq $os "windows" }}{{ $platform = "Windows" }}{{ end -}}
# Working on this machine: {{ $platform }}

What any agent should know about this machine before running commands on it. chezmoi writes this
file from rios0rios0/dotfiles (`.chezmoitemplates/home-agents.md`) and replaces it whenever that
changes, so edit it there. Inside a project, the project's own instructions come first.

## The machine

{{ if $wsl -}}
- Kali Linux on WSL 2, on Windows 11. Windows' drives are under `/mnt`.
- Projects live under `~/Development/<host>/<owner>/<repo>`, never on `/mnt/c`: builds there are
  slow and break file permissions.
- Windows programs run by name with `.exe` (`cmd.exe`, `powershell.exe`, `explorer.exe`). `ssh`,
  `ssh-add` and `op` in `~/.local/bin` run Windows' `ssh.exe`, `ssh-add.exe` and `op.exe`, so SSH
  keys and secrets stay in the Windows apps.
- `docker` is Docker Desktop's, through its WSL integration: it answers only while Docker Desktop
  runs on Windows.
{{- else if eq $os "linux" -}}
- Kali Linux. Projects live under `~/Development/<host>/<owner>/<repo>`.
{{- else if eq $os "android" -}}
- Termux on Android: no root, no `sudo`, no systemd. Packages come from `pkg install`, and
  `$PREFIX` (`/data/data/com.termux/files/usr`) stands where `/usr` would.
- `/tmp` is not writable: use `$TMPDIR` (`$PREFIX/tmp`).
- A `#!/usr/bin/env` or `#!/bin/sh` shebang works only through termux-exec, which Termux's shells
  preload. When a script fails with `bad interpreter`, run it through its interpreter
  (`bash script.sh`, `node script.js`).
- Programs linked against glibc do not start, because Termux's C library is bionic: prefer a Termux
  package, npm or a Go build over a downloaded Linux release.
- Android kills an app's processes past a budget of about 32 (`[Process completed (signal 9)]`):
  keep fan-outs small, and stop the background processes you start.
- Never leave a Go module cache (`pkg/mod`) under `$TMPDIR`: its read-only files crash Termux when
  it exits. To delete one, `chmod -R u+w` it first.
{{- else if eq $os "windows" -}}
- Windows 11. Development happens in WSL (the `kali-linux` distribution): projects live under
  `~/Development` inside it, never on a Windows drive.
- Run a command there with `wsl.exe -d kali-linux --exec zsh -c '<command>'`. `--exec` passes the
  arguments on as they are, where plain `wsl.exe` parses the line again in a shell, expanding `$`
  and dropping backslashes; `zsh -c` reads `~/.zshenv`, which puts the toolchains on `PATH`, and
  `bash -c` does not.
- Packages come from `winget`.
{{- end }}

## The shell

{{ if $zsh -}}
- zsh with Oh My Zsh. Every zsh reads `~/.zshenv`, which puts the toolchains on `PATH` and exports
  the cached credentials; only an interactive one reads `~/.zshrc`, where the aliases and functions
  below live, though some agent tools copy those into the shells they run commands in. `bash -c`
  reads neither file, so run toolchain commands through `zsh -c`.
- `cp`, `rm` and `mv` are functions that add `-i` whenever stdin is a terminal, so a command run in
  a terminal nobody answers can stop at an overwrite prompt. In anything automated, write
  `command cp`, `command rm` and `command mv` (`-f` cancels the `-i` for `rm` and `mv`, not for
  `cp`). Where Oh My Zsh's plain aliases are still loaded, `-i` reads end-of-file from a closed
  stdin, skips the operation and still exits 0: check that the file is there rather than trusting
  the exit code.
- `ls` is `eza -1 --classify --group-directories-first`: it marks names (`dir/`, `tool*`), quotes
  names that hold spaces, and takes eza's flags rather than GNU ls's. Use `command ls`, `find` or a
  glob when the output is parsed.
- An interactive zsh expands global aliases anywhere on a line: a bare `G`, `H`, `T`, `L`, `M`,
  `P`, `NE`, `NUL`, `CA` or `LL` turns into a pipe or a redirect (`H` is `| head`), and `...` into
  `../..`. Quote such words.
{{- else -}}
- PowerShell 7 (`pwsh`), in Windows Terminal. Windows PowerShell 5.1 (`powershell.exe`) is there
  too: it runs no profile under its `Restricted` execution policy and has no `&&` or `||`.
- Aliases point familiar names at cmdlets that take other arguments: `ls`, `cat`, `cp`, `mv`, `rm`,
  `echo`, `sort` and `where` (`Where-Object`). `rm -rf` fails, so write
  `Remove-Item -Recurse -Force`, and call `where.exe` for the native command. In 5.1, `curl` and
  `wget` are `Invoke-WebRequest` and `sc` is `Set-Content`: write `curl.exe` and `sc.exe`.
- A native program's failure does not stop a script: check `$LASTEXITCODE`. A cmdlet's error stops
  it only with `-ErrorAction Stop`.
- In 5.1, `>` and `Out-File` write UTF-16, and `Set-Content -Encoding UTF8` writes a BOM. Write
  files that other tools read from pwsh, or with `[System.IO.File]::WriteAllText($path, $text)`,
  which writes UTF-8 without one.
{{- end }}

## Quoting and escaping

{{ if $zsh -}}
- `$` expands inside double quotes and stays literal inside single quotes: single-quote anything
  that must arrive untouched (`'$VAR'`, `'*.go'`).
- Each layer parses the line again: the agent's tool, `zsh -c`, `ssh` to another machine
{{- if $wsl }},
  and `cmd.exe`, `powershell.exe` or `wsl.exe` on the way to Windows
{{- end }}. A `$` meant for the last layer needs one escape per layer, or single quotes at the
  outermost layer you control. For multi-line text, use a here-doc with a quoted delimiter
  (`<<'EOF'`): nothing inside it expands.
- An interactive zsh aborts a line whose glob matches nothing (`no matches found`), and a
  non-interactive one passes the glob on as it is (`NO_NOMATCH`). Either way a glob that matches
  is expanded, so `find . -name *.go` breaks once the directory holds a `.go` file. Quote patterns,
  and URLs or arguments holding `?`, `*` or `[` (`'https://host/path?q=1'`, `'pkg[extra]'`).
- zsh is not bash: an unquoted `$var` is not split into words (`${=var}` splits it), arrays start
  at 1, `path` is tied to `PATH` (a loop variable named `path` empties it), `status` is read-only,
  and `=word` at the start of a word becomes the path of the command `word` (`=ls` is
  `/usr/bin/ls`).
- `printf '%s\n'` rather than `echo -e`, and `$'...'` for ANSI-C escapes.
{{- else -}}
- `$` and backtick escapes (`` `n ``) expand inside double quotes; single quotes are literal, and a
  `'` inside them is doubled (`'it''s'`). The escape character is the backtick, not the backslash.
- Each layer parses the line again: PowerShell, then `cmd.exe` or `wsl.exe`, then the Linux shell.
  Single-quote at the outermost layer, prefer `wsl.exe --exec`, and hand JSON or other text full of
  double quotes to a native program through a file or stdin: Windows PowerShell 5.1 mangles the
  double quotes inside the arguments it passes on.
- `--%` passes the rest of a native command's line on unparsed.
{{- end }}
{{- if $zsh }}

## Git and GitHub

{{ if $wsl -}}
- Push and fetch over HTTPS through gh's credential helper, not SSH, whose agent path through
  1Password is unreliable here. Name the HTTPS URL, since `push origin` still goes over SSH when
  `origin` is an alias such as `git@github.com-mine:...`:
  `git -c credential.helper='!gh auth git-credential' push https://github.com/<owner>/<repo>.git HEAD:<branch>`.
- When commit signing fails because 1Password does not answer, commit with `--no-gpg-sign` and say
  so.
{{ end -}}
- CI requires a branch rebased on top of `main` before it is pushed: rebase first.
- Changes to the dotfiles go through a branch and a pull request on
  `github.com/rios0rios0/dotfiles`.
- The rules, agents, commands and skills under `~/.claude` and `~/.config/opencode` are synced by
  aisync: edit them in place, never in `~/.config/aisync/repo`, and never commit them to the
  dotfiles.

## Agent tools

- Claude Code loads the standards in `~/.claude/rules/` by itself, scoped by their frontmatter, and
  keeps subagents in `~/.claude/agents/`, slash commands in `~/.claude/commands/` and skills in
  `~/.claude/skills/`: use them rather than improvising. `/memory` lists the instruction files a
  session loaded, and `/context` what is in its context.
{{- if eq $os "linux" }}
- OpenCode is `ocode` (`~/.local/bin/ocode`, built from the `rios0rios0/opencode` fork), on the
  OmniRoute gateway at `{{ .omniroute.baseUrl }}`
{{- if $wsl }}, which runs from the dotfiles checkout
  (`local-services/omniroute/`)
{{- end }}. Models are `omniroute/<id>`, by default `omniroute/auto/coding`, with the tiers
  `auto/claude-opus`, `auto/claude-sonnet` and `auto/claude-haiku`. It loads no standards by
  itself: before starting, read the matching ones in `~/.config/opencode/rules/`, on demand --
  documentation and git-flow for every change; code-style, architecture, security and testing for
  code; the language's own rule; ci-cd before validating, committing or pushing. Its subagents are
  in `~/.config/opencode/agents/`, its commands in `~/.config/opencode/commands/`, and its skills
  only in `~/.config/opencode/skills/`.
{{- end }}
{{- end }}

## Secrets

- Secrets live in 1Password. Never print them, `.env` files, keys or tokens, and never put one on a
  command line, which other processes can read
{{- if ne $os "windows" }} in `/proc/<pid>/cmdline`{{ end }}:
  pass it through stdin or the environment.
{{- if $zsh }}
- Shells load them with `~/.scripts/linux-engineering-shell-credentials.sh`, cached at
  `~/.cache/op-credentials.env` (`OMNIROUTE_API_KEY` among them): read a credential from the
  environment, and never print the cache, age keys, `auth.json` or `service.json`.
{{- end }}
{{- if or $wsl (eq $os "windows") }}
- SSH keys stay in 1Password on Windows, so an SSH connection, a `git push` over SSH and a signed
  commit can each wait on an approval in the 1Password app. When one fails with
  `agent refused operation`, tell the user rather than retrying it in a loop.
{{- end }}
