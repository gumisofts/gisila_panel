# Production install

## Prerequisites

- Ubuntu 22.04+ or Debian 12 (fresh or existing)
- A non-root user with `sudo` access (or root)
- Port 80 and 443 open in your firewall
- A domain name pointed at the server (for TLS)
- **A reachable PostgreSQL 16+ database and Redis instance.** Neither is
  installed or managed by either installer below — the panel is a client of
  both, not their operator. They can be on the same host or fully
  remote/managed; point the installer at them with the `DB_*`/`REDIS_*` env
  vars described below.

If you don't already have Postgres/Redis, the quickest same-host setup is:

```bash
sudo apt-get install -y postgresql redis-server
sudo systemctl enable --now postgresql redis-server
sudo -u postgres psql -c "CREATE ROLE gisila LOGIN PASSWORD 'gisila';"
sudo -u postgres createdb --owner=gisila gisila_panel
```

The installers' defaults (`DB_HOST=localhost`, `DB_USER=gisila`,
`DB_PASSWORD=gisila`, `DB_NAME=gisila_panel`, `REDIS_HOST=127.0.0.1`,
`REDIS_PORT=6379`) match this setup exactly, so no extra env vars are needed
in that case.

## Option A: prebuilt install (recommended)

Downloads compiled binaries + the panel UI from a GitHub Release — no Dart
SDK, Node.js, or pnpm required, nothing compiled on the box:

```bash
curl -fsSL https://raw.githubusercontent.com/gumisofts/gisila_panel/main/infra/install-prebuilt.sh | sudo bash
```

Or, if you've already cloned the repo:

```bash
sudo bash infra/install-prebuilt.sh
```

Useful knobs (combine as needed):

```bash
sudo VERSION=0.1.0 bash infra/install-prebuilt.sh                  # pin a release
sudo RELEASE_FILE=/tmp/gisila-release-linux-x64.tar.gz \
     bash infra/install-prebuilt.sh                                # local artifact
sudo DB_HOST=10.0.0.5 DB_PASSWORD=secret \
     REDIS_HOST=10.0.0.5 REDIS_PASSWORD=secret \
     bash infra/install-prebuilt.sh                                # external DB/Redis
```

By default (`VERSION=latest`) it fetches from GitHub's
`.../releases/latest/download/…` URL, which only ever resolves to the newest
**non-draft, non-prerelease** release — if every published release so far is
a prerelease (common pre-1.0), that URL 404s. The script detects this and
automatically falls back to the newest release of *any* kind via the GitHub
API, so plain `VERSION=latest` keeps working either way; pass `VERSION=x.y.z`
if you want a specific release regardless.

## Option B: build from source

Prefer this only when you've changed the code and want to compile on the
host itself (requires the Dart SDK, and Node.js + pnpm if you also pass
`BUILD_FRONTEND=1`):

```bash
git clone https://github.com/gumisofts/gisila_panel.git /opt/gisila-panel
cd /opt/gisila-panel
sudo bash infra/install.sh
```

Same `DB_*`/`REDIS_*` knobs apply:

```bash
sudo DB_HOST=10.0.0.5 DB_PASSWORD=secret \
     REDIS_HOST=10.0.0.5 REDIS_PASSWORD=secret \
     bash infra/install.sh
```

Both installers are **idempotent** — safe to re-run after upgrades. Each one:

1. Installs system packages (Nginx, certbot, AppArmor, and — for `install.sh`
   only — the Dart SDK/build tools) plus the `psql` client. **Not**
   PostgreSQL or Redis themselves.
2. Checks connectivity to the configured PostgreSQL and Redis instances,
   failing fast with a clear error if either is unreachable.
3. Creates the `gisila` system user and `/srv/gisila/`, `/srv/apps/` layout.
4. Installs the compiled/prebuilt `gisila-panel`, `gisila-worker`, and
   `gisila-agent` binaries + panel UI.
5. Installs and enables systemd units for the API and worker.
6. Writes `/etc/gisila/.env` (random `JWT_SECRET`/admin password on first
   run) and `/etc/gisila/database.yaml`, then runs the schema migration.
7. Installs the Nginx panel vhost and starts everything.

When the script finishes:

```
✓ Gisila Panel installed successfully.
  Panel:  http://<server-ip>  (or your configured domain)
  Docs:   http://<server-ip>/docs
  Admin:  http://<server-ip>/admin

  PostgreSQL: gisila@<DB_HOST>:<DB_PORT>/gisila_panel (external, /etc/gisila/database.yaml)
  Redis:      <REDIS_HOST>:<REDIS_PORT> (external, /etc/gisila/.env)
```

## Wire your domain

1. Point a DNS A record at the box: `panel.your-domain.tld → <ip>`.
2. Edit the nginx vhost:
   ```bash
   sudo sed -i 's/panel\.example\.com/panel.your-domain.tld/' \
     /etc/nginx/sites-available/gisila-panel
   sudo nginx -t && sudo systemctl reload nginx
   ```
3. Issue a certificate:
   ```bash
   sudo certbot --nginx -d panel.your-domain.tld
   ```

## Configuration

`/etc/gisila/.env` controls runtime behaviour:

| Variable | Purpose |
|---|---|
| `PORT` | API HTTP port (default 8000). |
| `JWT_SECRET` | HMAC secret. Rotate by editing + `systemctl restart gisila-panel`. |
| `JWT_EXPIRE_DAYS` | JWT lifetime. |
| `STUDIO_USERNAME` / `STUDIO_PASSWORD` | Credentials for `/admin`. |
| `REDIS_HOST` / `REDIS_PORT` | Redis connection (set at install time via `REDIS_HOST`/`REDIS_PORT`). |
| `REDIS_PASSWORD` | Redis auth password, if the instance requires one (`REDIS_PASSWORD`). |
| `APPS_ROOT` | Where per-app filesystems live (default `/srv/apps`). |
| `APP_PORT_RANGE_MIN/MAX` | Internal port pool for new apps. |
| `AGENT_BIN` | Path to the privileged agent binary. |
| `NODE_ID` | Used when you scale beyond a single host. |

`/etc/gisila/database.yaml` points at PostgreSQL — an external instance you
configured with the installer's `DB_HOST`/`DB_PORT`/`DB_NAME`/`DB_USER`/
`DB_PASSWORD`/`DB_SSL` env vars, never installed by the panel itself. Both
files are owned `gisila:gisila`, mode `0640`.

## Logs

```bash
journalctl -fu gisila-panel
journalctl -fu gisila-worker
journalctl -fu gisila-app_xxx     # any user app
```

## Updating

```bash
# prebuilt install
sudo bash infra/install-prebuilt.sh          # re-running is safe; picks up the newest release
sudo VERSION=x.y.z bash infra/install-prebuilt.sh   # pin a specific version

# source install
cd /opt/gisila-panel    # wherever you cloned
git pull
sudo bash infra/install.sh   # re-running is safe; binaries are replaced atomically
```

## Uninstall

```bash
sudo bash infra/uninstall.sh          # control plane only, leaves apps + DB/Redis data
sudo bash infra/uninstall.sh --apps   # also removes every user app and /srv/apps
sudo bash infra/uninstall.sh --purge  # also drops the gisila_panel DB/role + gisila:* Redis keys
sudo bash infra/uninstall.sh --all    # both of the above
```

`--purge`'s database/Redis cleanup is a best-effort, same-host convenience
(it only works when Postgres/Redis are reachable via `sudo -u postgres` /
local `redis-cli`). For a remote or externally-managed instance, drop the
database/role and flush `gisila:*` keys yourself.
