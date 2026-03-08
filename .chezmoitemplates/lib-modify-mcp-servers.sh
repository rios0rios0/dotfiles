# Shared MCP server merge logic for modify_ scripts.
# Receives current JSON on stdin, outputs merged JSON on stdout.

_mcp_log() { printf '[mcp-servers] %s\n' "$*" >&2; }

_script="$(mktemp)"
trap 'rm -f "$_script"' EXIT
cat > "$_script" << 'PYEOF'
import json, os, sys

OS = os.environ.get("CHEZMOI_OS", "linux")

current = sys.stdin.read().strip()
if current:
    try:
        data = json.loads(current)
    except json.JSONDecodeError:
        print(f"[mcp-servers] WARN: invalid JSON input, starting fresh", file=sys.stderr)
        data = {}
else:
    data = {}

if OS == "android":
    desired_servers = {
        "github": {
            "type": "http",
            "url": "https://api.githubcopilot.com/mcp/",
            "headers": {
                "Authorization": "Bearer ${GITHUB_PERSONAL_ACCESS_TOKEN}"
            }
        }
    }
else:
    desired_servers = {
        "github": {
            "type": "stdio",
            "command": "docker",
            "args": [
                "run", "-i", "--rm",
                "-e", "GITHUB_PERSONAL_ACCESS_TOKEN",
                "ghcr.io/github/github-mcp-server"
            ],
            "env": {
                "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_PERSONAL_ACCESS_TOKEN}"
            }
        },
        "azure-devops": {
            "type": "stdio",
            "command": "docker",
            "args": [
                "run", "-i", "--rm",
                "-e", "ADO_ORG",
                "-e", "ADO_MCP_AUTH_TOKEN",
                "ghcr.io/helgeu/ado-mcp-docker-img"
            ],
            "env": {
                "ADO_ORG": "${ADO_ORGANIZATION_NAME}",
                "ADO_MCP_AUTH_TOKEN": "${ADO_PERSONAL_ACCESS_TOKEN}"
            }
        },
        "sonarqube": {
            "command": "docker",
            "args": [
                "run", "-i", "--rm",
                "-e", "SONARQUBE_URL",
                "-e", "SONARQUBE_TOKEN",
                "mcp/sonarqube"
            ],
            "env": {
                "SONARQUBE_URL": "${SONARQUBE_URL}",
                "SONARQUBE_TOKEN": "${SONARQUBE_TOKEN}"
            }
        },
        "kubernetes": {
            "type": "stdio",
            "command": "npx",
            "args": [
                "-y",
                "kubernetes-mcp-server@latest"
            ]
        }
    }

servers = data.setdefault("mcpServers", {})
for name, config in desired_servers.items():
    servers[name] = config

print(f"[mcp-servers] merged {len(desired_servers)} servers for OS={OS}", file=sys.stderr)
json.dump(data, sys.stdout, indent=2)
sys.stdout.write("\n")
PYEOF

export CHEZMOI_OS="{{ .chezmoi.os }}"
if ! python3 "$_script"; then
    _mcp_log "ERROR: Python script failed"
    exit 1
fi
