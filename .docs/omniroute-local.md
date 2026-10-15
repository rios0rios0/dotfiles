# Local OmniRoute for Claude Code

OmniRoute can route a Claude Code session through multiple model providers while the Claude interface stays open. Its Compose stack and local environment files live in `local-services/omniroute/`. The dashboard and API run locally, with Redis available only on the internal Docker network. Compose keeps the existing `dotfiles` project name so moving the files does not switch to new named data volumes.

## Start OmniRoute

Run these commands from `local-services/omniroute/`. Copy the environment template and restrict its permissions:

```bash
cp .env.example .env
chmod 600 .env
```

Generate and set four values in `.env`:

| Variable | Generate with | Purpose |
|----------|---------------|---------|
| `JWT_SECRET` | `openssl rand -base64 48` | Signs dashboard sessions |
| `API_KEY_SECRET` | `openssl rand -hex 32` | Encrypts provider API keys |
| `INITIAL_PASSWORD` | `openssl rand -hex 24` | First dashboard login password |
| `STORAGE_ENCRYPTION_KEY` | `openssl rand -hex 32` | Encrypts the local database |

Keep these values private and preserve them across restarts. Changing the encryption keys can make stored data or provider credentials unreadable.

Start the services and open the dashboard:

```bash
docker compose up -d
docker compose logs -f omniroute
```

Open `http://127.0.0.1:20128`. The initial dashboard setup may ask for a bootstrap token; find it in the `omniroute` service logs. Create a dashboard API key for Claude Code after signing in.

The Compose file uses a pinned OmniRoute `v3.8.51` `linux/amd64` image digest. Both services use `restart: always`, so Docker starts them automatically when its daemon starts. All published ports bind to `127.0.0.1`; Redis has no host-published port. `docker compose down` preserves the named data volumes. `docker compose down -v` deletes the database, Redis data, and configured provider credentials.

### Fix Redis snapshot permission errors

If Redis logs `Failed opening the temp RDB file ... /data ... Permission denied`, recreate Redis after updating the Compose file. Do not override Redis capabilities in Compose: the image needs `CHOWN`, `SETUID` and `SETGID` to repair the data volume ownership, then drop to its unprivileged user before starting the server.

```bash
docker compose up -d --force-recreate redis
docker compose logs --tail=50 redis
```

This recreates only the Redis container and keeps the named Redis data volume.

## Fix provider TLS validation

If NVIDIA NIM or OpenRouter reports `SELF_SIGNED_CERT_IN_CHAIN` or `fetch failed` while validating a key, the request is reaching a TLS certificate authority that the container does not trust. This is a certificate trust problem, not evidence that the API key is invalid. The Compose service adds the host CA bundle to Node.js trust through a read-only mount. On Linux, it defaults to `/etc/ssl/certs/ca-certificates.crt`.

If you use Windows with WSL and the CA is trusted only by Windows, open `certmgr.msc` (current-user store) or `certlm.msc` (local-machine store). Under **Trusted Root Certification Authorities > Certificates**, export the network's trusted root CA as **Base-64 encoded X.509 (.CER)** and choose not to export a private key. Copy the certificate into a WSL path readable by the container process, then set `OMNIROUTE_CA_BUNDLE` in `local-services/omniroute/.env` to that absolute path. The variable can also point to a PEM bundle containing multiple trusted certificates. Only add a CA you trust.

Recreate OmniRoute so Docker applies the new mount and environment setting, then retry provider validation:

```bash
docker compose up -d --force-recreate omniroute
```

Do not disable TLS certificate verification to work around this error.

## Add providers and route requests

In the OmniRoute dashboard, open **Providers**, connect the NVIDIA NIM, OpenRouter and Baseten providers, and add their API keys. Test each connection, then enable the providers and models you want the router to consider. Create an OmniRoute API key for Claude Code from its API key management page.

OmniRoute supports automatic model selection through `auto/coding`. In zsh, start a Claude session against the local gateway like this; the API key is read without putting it in shell history:

```zsh
read -s 'OMNIROUTE_API_KEY?Paste the OmniRoute API key: '
print
ANTHROPIC_BASE_URL='http://127.0.0.1:20128' \
ANTHROPIC_AUTH_TOKEN="$OMNIROUTE_API_KEY" \
ANTHROPIC_MODEL='auto/coding' \
claude
unset OMNIROUTE_API_KEY
```

This only redirects the Claude process started by that command; it leaves the regular Claude profile, `claudex`, `claude-local` and `claude-remote` configuration untouched. Restart the Claude process after changing gateway settings because Claude Code reads these environment variables at startup.

## Privacy boundary

The dashboard, routing API, provider credentials and database remain on this machine. Prompts sent to NVIDIA, OpenRouter or Baseten still leave the machine and are handled under that provider's own retention and usage policies. Use only providers and models whose data terms fit the prompt you send.
