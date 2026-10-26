# Production install

## Prerequisites

- Ubuntu 22.04+ or Debian 12+ (fresh or existing; x64 or arm64)
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
DB_PW="$(openssl rand -hex 16)"; REDIS_PW="$(openssl rand -hex 24)"
sudo -u postgres psql -c "CREATE ROLE gisila LOGIN PASSWORD '$DB_PW';"
sudo -u postgres createdb --owner=gisila gisila_panel
echo "requirepass $REDIS_PW" | sudo tee -a /etc/redis/redis.conf >/dev/null
sudo systemctl restart redis-server
echo "DATABASE_URL='postgresql://gisila:$DB_PW@localhost:5432/gisila_panel'"
echo "REDIS_URL='redis://:$REDIS_PW@127.0.0.1:6379'"
```

Pass the two printed URLs to the installer (see below).

### Connection security

Postgres and Redis can be on this host, on your LAN or with a managed
provider. The installer only refuses setups that would leave them open. Apps
hosted by the panel run on the same machine, so `127.0.0.1` is reachable by
every one of them and is not treated as private.

| Refused | Why |
|---|---|
| Redis with no password, or one under 16 characters | Any hosted app could read and inject panel jobs. |
| A well-known Postgres password (`gisila`, `postgres`, …) or one under 12 characters | Any hosted app could log in as the panel. |
| Postgres or Redis on a public address without TLS | Credentials and data cross the internet in plain text. Use `?sslmode=require` / `rediss://`. |

Postgres or Redis on a private network without TLS, and a local Postgres or
Redis listening on a public interface, are allowed with a warning.
`GISILA_ALLOW_INSECURE=1` turns the refusals into warnings for throwaway test
machines; never use it on a host that runs other people's apps.

## Option A: prebuilt install (recommended)

Downloads compiled binaries + the panel UI from a GitHub Release — no Dart
SDK, Node.js, or pnpm required, nothing compiled on the box. Published for
**linux-x64** and **linux-arm64** (auto-detected via `uname -m`):

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
sudo RELEASE_FILE=/tmp/gisila-release-linux-arm64.tar.gz \
     bash infra/install-prebuilt.sh                                # local artifact (x64 or arm64)

# Preferred: URLs + domain (pass env to bash, not to curl)
curl -fsSL https://raw.githubusercontent.com/gumisofts/gisila_panel/main/infra/install-prebuilt.sh \
  | sudo env \
      DATABASE_URL='postgresql://gisila:<db-password>@10.0.0.5:5432/gisila_panel' \
      REDIS_URL='rediss://:<redis-password>@10.0.0.5:6379' \
      PANEL_DOMAIN=panel.example.com \
      ISSUE_TLS=1 \
      bash
```

`DATABASE_URL` / `REDIS_URL` replace the discrete `DB_*` / `REDIS_*` vars.
`PANEL_DOMAIN` is written into the nginx vhost; `ISSUE_TLS=1` runs certbot.

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

Same URL / domain knobs apply:

```bash
sudo DATABASE_URL='postgresql://gisila:<db-password>@10.0.0.5:5432/gisila_panel' \
     REDIS_URL='redis://:<redis-password>@10.0.0.5:6379' \
     PANEL_DOMAIN=panel.example.com \
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

Prefer setting it at install time (`PANEL_DOMAIN=…`, optional `ISSUE_TLS=1`).
Or afterwards:

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
| `JWT_SECRET` | HMAC secret; required (the panel refuses to start without it). Rotate by editing + `systemctl restart gisila-panel`, which signs everyone out. |
| `JWT_EXPIRE_DAYS` | JWT lifetime. |
| `STUDIO_ENABLED` | `1` mounts GisilaStudio (raw DB admin) at `/admin`; anything else (the default) leaves it off. Set at install with `ENABLE_STUDIO=1`, or edit + `systemctl restart gisila-panel`. |
| `STUDIO_USERNAME` / `STUDIO_PASSWORD` | Credentials for `/admin` when the studio is enabled. It stays unmounted if the password is empty or a default such as `admin`. |
| `LOG_LEVEL` | `trace`/`debug`/`info` (default)/`warning`/`error`. |
| `REDIS_HOST` / `REDIS_PORT` | Redis connection (from `REDIS_URL` or discrete vars at install). |
| `REDIS_PASSWORD` | Redis auth password. Required by the installer (see Connection security). |
| `REDIS_USERNAME` | Redis ACL user, for managed providers. Empty authenticates as `default`. |
| `REDIS_TLS` | `true` connects over TLS; set automatically from a `rediss://` URL. |
| `PANEL_DOMAIN` | Hostname for the panel nginx vhost (set at install via `PANEL_DOMAIN`). |
| `APPS_ROOT` | Where per-app filesystems live (default `/srv/apps`). |
| `APP_PORT_RANGE_MIN/MAX` | Internal port pool for new apps. |
| `AGENT_BIN` | Path to the privileged agent binary. |
| `NODE_ID` | Used when you scale beyond a single host. |

`/etc/gisila/database.yaml` points at PostgreSQL — usually written from
`DATABASE_URL` at install time (or discrete `DB_*` vars). Never installed by
the panel itself. Both files are owned `gisila:gisila`, mode `0640`.

### Changing the Postgres or Redis connection later

`database.yaml` is rewritten on every install run, so re-running the installer
with a new `DATABASE_URL` moves the panel to a different Postgres. `.env` is
deliberately *not* rewritten (it holds secrets and operator edits), so the
Redis keys are refreshed only when you actually pass Redis details on that run:

```bash
sudo env REDIS_URL='redis://:<redis-password>@10.0.0.9:6379' bash infra/install.sh
```

Without a `REDIS_URL`/`REDIS_*` on the command line, the existing `REDIS_HOST`
is left alone. You can also edit `/etc/gisila/.env` by hand and
`systemctl restart gisila-panel gisila-worker`.

### Running Postgres or Redis on another machine

Both are supported, together or separately — the panel's systemd units order
themselves behind a local `postgresql.service` / `redis-server.service` when
one exists, but never require it, so a host with neither installed still
starts.

One thing changes in the UI: the Databases page surfaces the panel's own
cluster as a read-only **system database**. When that cluster is remote, the
panel is purely its client — it reads live metrics and settings over the
connection from `database.yaml`, and hides everything that would need a local
`psql`, `pg_dump`, data directory or systemd unit (creating databases and
roles, applying settings, backups, public exposure, start/stop). Manage those
on the machine the cluster runs on. Connection and throughput counters come
back slightly coarser there too: the panel authenticates as its own role rather
than the `gisila_monitor` role it provisions on local clusters, and Postgres
hides other users' session state from a non-superuser.

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

`--purge` flushes `gisila:*` from whichever Redis `/etc/gisila/.env` names,
including a remote or password-protected one. The Postgres side is a
same-host convenience only (it goes through `sudo -u postgres`); for a remote
or externally-managed cluster, drop the database and role yourself.
