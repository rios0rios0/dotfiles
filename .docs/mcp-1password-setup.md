# MCP Credentials in 1Password

The MCP servers that `modify_dot_claude.json` merges into `~/.claude.json` never hold a secret.
Each one names an environment variable as `${NAME}`, and Claude Code fills it in when it starts
the server. On Linux and Android those variables come from `cred:NAME` fields on the machine's
device note, which `dot_scripts/linux-engineering-shell-credentials.sh` exports at shell start and
caches for non-interactive shells (see "Runtime Credential Lifecycle" in `CLAUDE.md`). Which
servers each platform gets, and why each has the shape it has, is in "MCP Servers" in `CLAUDE.md`.

## The field to add

On the `Device: <deviceName>` Secure Note in the `personal` vault, add one concealed (password)
field per variable a server on that machine needs, labelled `cred:` followed by the variable name:

| Field label             | Server   | Platforms               |
|-------------------------|----------|-------------------------|
| `cred:CONTEXT7_API_KEY` | Context7 | Linux, Windows, Android |

Chrome DevTools needs no credential, so it has no field.

Then run `reload-credentials` and restart Claude Code. A server whose variable is still unset gets
the literal `${NAME}` text instead of a value, and `claude mcp list` reports it as
`Missing environment variables: NAME`. For Context7 that means every call fails with
`Invalid API key` rather than falling back to the anonymous tier.

Until 2026-10-14 this repository also configured GitHub, Azure DevOps and SonarQube servers, which
read `cred:GITHUB_PERSONAL_ACCESS_TOKEN`, `cred:ADO_ORGANIZATION_NAME`,
`cred:ADO_PERSONAL_ACCESS_TOKEN`, `cred:SONARQUBE_URL` and `cred:SONARQUBE_TOKEN`. Those servers
were retired in favour of their CLIs, so keep those fields only where a CLI or script still reads
them.

## Windows

Windows has no runtime loader for `cred:` fields. Set the variables a server needs as user
environment variables in System Properties, Environment Variables, which keeps the values out of
shell history, and restart Claude Code.
