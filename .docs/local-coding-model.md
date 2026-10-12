# Local Coding Model for Claude Code

This optional WSL setup routes Claude Code through a local Ollama model for routine coding work. It keeps the existing `claude` command and Anthropic login intact; `claude-local` applies provider settings only to its own process.

The setup scripts are managed in this repository because Ollama installation, GPU service settings, and CLI launchers are environment configuration. AI instructions and coding standards remain in the separate `aifiles` repository.

## Local WSL Setup

Requirements:

- WSL2 with NVIDIA GPU support and `nvidia-smi` available
- systemd enabled in WSL
- Claude Code already installed
- `curl` and `sudo`

Apply the dotfiles, then run:

```bash
chezmoi apply
ollama-claude-setup
```

The setup command installs Ollama from its official HTTPS installer when missing, creates a systemd override with a 65,536-token default context, starts the service, and downloads `qwen3.8:27b`. The current Ollama library build is a Q4_K_M model around 18 GB; model tags can change as the upstream publisher updates them. See the [Ollama model page](https://ollama.com/library/qwen3.8:27b).

Start a local coding session with:

```bash
claude-local
```

After `chezmoi apply`, reload Zsh once with `source ~/.zshrc` (or open a new terminal). To switch providers, exit the current Claude Code process and run `claude-switch` for a prompt, or select a provider directly:

```bash
claude-switch local --resume
claude-switch claude --resume
```

The current session cannot change its API endpoint in place; the provider is selected when Claude Code starts. `--resume` passes through to the selected CLI, letting you try to reopen a conversation under the other provider; if that transcript is incompatible, start fresh. Resuming sends the stored conversation to the selected provider, so switching from local to Anthropic sends that transcript to Anthropic. You can also use `claude-switch local` or `claude-switch claude` to start a fresh session.

The launcher sets `ANTHROPIC_BASE_URL`, a placeholder Ollama auth token, the model and context variables, and clears Anthropic API-key and cloud-provider overrides for that process. It checks that Ollama responds before starting Claude Code. Select a model per session with `CLAUDE_LOCAL_MODEL`; to change context, update the Ollama service and launcher to the same value:

```bash
ollama-claude-setup --context 32768
CLAUDE_LOCAL_CONTEXT_TOKENS=32768 \
claude-local
```

The setup command changes the Ollama service context; `CLAUDE_LOCAL_CONTEXT_TOKENS` must match it. The setup default is 65,536 tokens, a coding-oriented context that may need lowering if the GPU runs out of memory or Ollama offloads layers to the CPU. Check placement and allocated context with `ollama ps`.

Pass normal Claude Code arguments through the launcher, including an explicit model override:

```bash
claude-local --model qwen3.8:27b
claude-local --resume
```

The launcher uses Ollama's [Anthropic Messages API compatibility](https://ollama.com/blog/claude). It does not edit `~/.claude/settings.json`, rotate accounts, or change the normal `claude` command. Ollama's API stays on its loopback listener by default.

## Remote RTX 4090

Install Ollama on the remote desktop, pull the same model there, and keep the Ollama API bound to loopback. The 27B model uses about 18 GB before context memory, so the 4090 may need a smaller context or CPU offload. Start at 16,384 tokens and check placement with `ollama ps`; lower it if the model does not fit fully in VRAM. Configure the Ollama server/app to use the same context. From WSL, forward a local port over SSH:

```bash
ssh -N -L 11435:127.0.0.1:11434 <gpu-host>
```

In a second WSL terminal, route a session through that tunnel:

```bash
CLAUDE_LOCAL_BASE_URL=http://127.0.0.1:11435 \
CLAUDE_LOCAL_CONTEXT_TOKENS=16384 \
claude-local
```

For a Windows remote host, install Ollama from the [official Windows download](https://ollama.com/download/windows), use PowerShell to pull `qwen3.8:27b`, and set its context length to 16,384 in Ollama's app settings. Keep Ollama running while the SSH tunnel is open. Do not expose port `11434` directly to the internet or an untrusted network; Ollama's local API does not require authentication.

The local 5090 and remote 4090 are independent Ollama workers. Start separate Claude Code sessions and point each one at its worker; their VRAM is not combined. Use the remote endpoint only when its host is reachable over SSH or a trusted private network.

## Quality Workflow

- Use the local model first for well-scoped, low-risk issues with clear acceptance criteria.
- Require the repository's normal tests, lint, build, and CI checks before merging.
- Review the diff and test behavior; do not treat a model's report that checks passed as evidence.
- Escalate ambiguous requirements, security-sensitive changes, migrations, architecture, and repeated failures to Claude Sonnet/Opus or a human reviewer.
- Track rework and defects on a representative issue sample before moving higher-risk work to the local model.

## Troubleshooting

- Check GPU visibility with `nvidia-smi` from WSL.
- Check service state with `systemctl status ollama.service`.
- Check that the model is installed with `ollama list`.
- If a local session cannot reach Ollama, verify `CLAUDE_LOCAL_BASE_URL` and the `/api/tags` endpoint.
- If Claude Code compacts too early or Ollama reports context errors, keep the launcher's context value aligned with the service context and lower it when VRAM is constrained.

References: [Ollama install](https://ollama.com/download/linux), [Ollama context length](https://docs.ollama.com/context-length), [Claude Code environment variables](https://code.claude.com/docs/en/env-vars).
