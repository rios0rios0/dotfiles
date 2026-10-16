# OpenCode V2 Through OmniRoute

OpenCode is the second client of the local [OmniRoute](omniroute-local.md) gateway:
`chezmoi apply` renders `dot_config/opencode/opencode.json.tmpl` to
`~/.config/opencode/opencode.json`, making OmniRoute the primary provider and
`omniroute/auto/coding` the default model. No model list lives in this repository for OpenCode
-- unlike `claude-omni`, whose listed models come from `.chezmoidata/omniroute.yaml`, OpenCode
discovers the catalog from the gateway's own `/v1/models`, which serves exactly what the API
key's policy allows. A model, or a whole new provider, added in OmniRoute's dashboard appears
in OpenCode without a change here.

## What is configured

| Part | Where it comes from |
|------|---------------------|
| Provider | `providers.omniroute`: `baseURL` is `.chezmoidata/omniroute.yaml`'s `baseUrl` with `/v1`, and the key is the `{env:OMNIROUTE_API_KEY}` reference |
| Model list | live from the gateway; the `omniroute/*` entries in the model picker and `opencode models` |
| Default model | `omniroute/auto/coding`: the gateway picks the upstream |
| MCP servers | context7 (remote, every platform) and Chrome DevTools (local, Linux only, pinned like Claude Code's) |
| Permissions | the same shell, read and edit allowances as the Claude Code side, as V2 ordered entries |
| Rules | `~/.config/opencode/AGENTS.md`, applied by chezmoi, plus every project's `CLAUDE.md` through `instructions` |
| Reference | `dotfiles` points at the chezmoi source, so a session can read the dotfiles that rendered the configuration |
| Terminal look | `~/.config/opencode/cli.json` |

The key is the same `cred:OMNIROUTE_API_KEY` field of the device note `claude-omni` uses: the
credential loader exports `OMNIROUTE_API_KEY` in every shell, and OpenCode substitutes it when
it loads the file. The repository itself never holds it.

## Using it

```bash
opencode                       # in a project; the picker lists every model the key allows
opencode models                # the full catalog, with the omniroute/* entries among them
```

Model ids are the ones OmniRoute uses, so any id from the picker (`omniroute/auto/coding`,
`omniroute/codex/...`, `omniroute/nvidia/...`) can also be passed verbatim to
`claude-omni -m` or `claude-omni-task -m`.

## When models are missing

- **The gateway is down.** While OmniRoute does not answer, the provider serves no models;
  start it with `docker compose up -d` from `local-services/omniroute/`. Nothing else in
  OpenCode is affected.
- **The key is missing.** In an environment without the credential loader (a cron job, an
  IDE), `{env:OMNIROUTE_API_KEY}` substitutes empty, the gateway answers 401 and the models
  disappear. Run OpenCode from an interactive shell, or export the key first.
- **A model the key does not allow.** The list is OmniRoute's key policy; allow the model or
  the combo in its dashboard rather than adding anything here.
- **Nothing at all is loaded.** V1 habits fail silently: the MCP field is `environment`, not
  `env`, and a key written as `${OMNIROUTE_API_KEY}` stays literal and fails authentication.
  `make test-opencode` guards both by rendering the template on each platform and checking
  every field, and `opencode debug config` shows what was actually loaded.

## References

- [The gateway, its keys and `claude-omni`](omniroute-local.md)
- [OpenCode configuration](https://opencode.ai/docs/config)
