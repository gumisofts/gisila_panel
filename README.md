# Gisila Panel

A modern, open-source, **lightweight PaaS hosting panel** optimized for compiled backend applications (Dart, Go, Rust, Zig, Bun, Node.js, Python).

Works like Heroku / Railway / Render / Coolify — but instead of relying on Docker / Kubernetes, it focuses on **ultra-lightweight native Linux execution** with systemd sandboxing, isolated Linux users, AppArmor, cgroups v2, seccomp, and Nginx reverse proxying.

## Core philosophy

- High-density hosting — pack many apps onto a small VPS.
- Low RAM usage — no per-app container daemon.
- Low-cost VPS friendly — comfortable on a 1 GB / 1 vCPU box.
- Minimal overhead — straight `exec` of native binaries via systemd.
- Secure multi-tenant — every app gets its own Linux user + sandbox.
- Optimized for compiled backend apps.
- Open-source first, self-hostable, modern UI/UX.

## Tech stack

| Layer | Tech |
|---|---|
| Frontend | Next.js 15 (App Router) · TypeScript · Tailwind CSS · shadcn/ui |
| Backend  | **Dart** · `gisila` (Shelf MVC) · `gisila_orm` · `gisila_doc` · `gisila_studio` |
| DB       | PostgreSQL 16 |
| Cache / queue | Redis 7 |
| Workers  | `gisila_jobs` — Redis-backed Dart task queue (the Celery replacement) |
| Real-time| WebSockets (logs / events stream) |
| OS       | Ubuntu 22.04+ |
| Runtime  | systemd · Nginx · AppArmor · cgroups v2 · seccomp |
| TLS      | Let's Encrypt (`certbot`) |
| Logs     | `journalctl` |

## High-level architecture

```text
┌────────────────────────────────────────────────────────────────────┐
│                         Gisila Panel                               │
│                                                                    │
│   ┌──────────────┐   HTTPS   ┌──────────────────┐                  │
│   │  Next.js UI  │ ────────▶ │  Dart API server │                  │
│   └──────────────┘           │  (gisila stack)  │                  │
│                              └─┬─────────────┬──┘                  │
│                                │             │                     │
│                                ▼             ▼                     │
│                          ┌──────────┐  ┌──────────┐                │
│                          │ Postgres │  │  Redis   │                │
│                          └──────────┘  └─────┬────┘                │
│                                              │ jobs                │
│                                              ▼                     │
│                                  ┌───────────────────┐             │
│                                  │  gisila-worker    │ (Dart)      │
│                                  │  (deployment      │             │
│                                  │   orchestrator)   │             │
│                                  └────────┬──────────┘             │
│                                           │                        │
│                  IPC (unix socket / sudo) │                        │
│                                           ▼                        │
│      ┌──────────────────────────────────────────────────────┐      │
│      │            gisila-agent (root, host-side)            │      │
│      │  user/dir provisioning · port alloc · systemd unit   │      │
│      │  generation · nginx vhost · apparmor profile · cert  │      │
│      │  issuance · journald tail                            │      │
│      └──────────────────────────────────────────────────────┘      │
│                                                                    │
│              ┌────────┬────────┬────────┬────────┐                 │
│              │ app1   │ app2   │ app3   │ appN   │ (per-Linux-user)│
│              │ systemd│ systemd│ systemd│ systemd│ isolated        │
│              └────────┴────────┴────────┴────────┘                 │
└────────────────────────────────────────────────────────────────────┘
```

## Repository layout

```text
gisila-panel/
├── backend/                # Dart API server (gisila stack) + worker
│   ├── bin/server.dart     # HTTP entry point (multi-isolate + hot-reload)
│   ├── bin/worker.dart     # Background worker entry point
│   ├── bin/migrate.dart    # Migration entry point (re-exports gisila_orm)
│   ├── lib/
│   │   ├── server.dart     # GisilaApp wiring
│   │   ├── admin.dart      # GisilaStudio registrations
│   │   ├── config.dart     # env + db + redis config
│   │   ├── endpoints/      # Controllers
│   │   ├── forms/          # Typed input bodies
│   │   ├── services/       # Business logic
│   │   ├── infra/          # Auth, DB provider, error mapper, redis client
│   │   ├── workers/        # Background job handlers
│   │   ├── utils/          # JWT, ports, slugs, randoms
│   │   └── models/         # schema.gisila.yaml + generated code
│   ├── database.yaml
│   ├── docker-compose.yaml # Postgres + Redis
│   └── pubspec.yaml
│
├── agent/                  # Host-side privileged agent (Dart)
│   ├── bin/gisila-agent.dart
│   ├── lib/generators/     # systemd, nginx, apparmor templates
│   ├── lib/runtime/        # exec, port alloc, journald tail
│   └── templates/          # *.tmpl files
│
├── frontend/               # Next.js 15 dashboard (TypeScript + Tailwind + shadcn/ui)
│   ├── app/                # App router pages
│   ├── components/
│   ├── lib/                # API client + hooks
│   └── package.json
│
├── infra/                  # Production install assets
│   ├── install.sh
│   ├── uninstall.sh
│   ├── gisila-panel.service
│   ├── gisila-worker.service
│   ├── gisila-apps.target
│   ├── nginx-panel.conf
│   └── sudoers.d_gisila
│
├── docs/                   # Architecture / API / security / roadmap
└── scripts/                # Dev helpers
```

---

## Quick start (development) — Docker only

You don't need Dart, Node, or pnpm on your machine. Just Docker.

```bash
git clone https://github.com/your-org/gisila-panel.git
cd gisila-panel
docker compose up
```

That's it. The first start runs migrations + code generation automatically, then brings up:

| Service            | URL                                           |
|--------------------|-----------------------------------------------|
| Next.js frontend   | <http://localhost:3000>                       |
| Dart API           | <http://localhost:8000>                       |
| API docs (Swagger) | <http://localhost:8000/docs>                  |
| Admin panel        | <http://localhost:8000/admin> (`admin`/`admin`) |
| Postgres           | `localhost:5455` (`postgres`/`postgres`)      |
| Redis              | `localhost:6380`                              |

The whole `gisila_tools/` workspace is bind-mounted, so editing Dart or TypeScript code on your host triggers hot reload in the matching container.

### Common dev commands

```bash
./scripts/dev.sh                  # same as `docker compose up`
./scripts/dev.sh up -d            # detach
./scripts/dev.sh logs -f api      # tail just the API logs
./scripts/dev.sh down             # stop (keep DB)
./scripts/dev.sh reset            # wipe ALL volumes (start clean)

./scripts/build_runner.sh         # re-run code generation after schema/controller edits
./scripts/migrate.sh up           # apply new migrations
./scripts/psql.sh                 # psql shell into the dev database
./scripts/redis-cli.sh            # redis-cli into the dev redis
```

> **Note:** The worker uses `AGENT_MODE=dev` in the compose stack — it logs the commands it *would* send to `gisila-agent` but doesn't actually touch systemd / Nginx / AppArmor. Use the production install on a real Ubuntu host (`infra/install.sh`) to test real deployments end-to-end.

---

## Production install (single node)

### Prerequisites

- Ubuntu 22.04+ or Debian 12 (fresh or existing)
- A non-root user with `sudo` access (or root)
- Port 80 and 443 open in your firewall
- A domain name pointed at the server (for TLS)

### Quick install — prebuilt (recommended)

The fastest way to stand up a node. This installs **prebuilt** binaries and the
prebuilt panel UI from a GitHub Release — no Dart SDK, Node.js, or pnpm, and
nothing is compiled on the box. One command, no clone required:

```bash
curl -fsSL https://raw.githubusercontent.com/gumisofts/gisila_panel/main/infra/install-prebuilt.sh | sudo bash
```

Or, if you've already cloned the repo:

```bash
sudo bash infra/install-prebuilt.sh
```

Useful knobs:

```bash
sudo VERSION=0.1.0 bash infra/install-prebuilt.sh         # pin a release
sudo RELEASE_FILE=/tmp/gisila-release-linux-x64.tar.gz \  # install a local artifact
     bash infra/install-prebuilt.sh
```

It performs the same system setup as the source installer below (PostgreSQL,
Redis, Nginx, systemd, config, migrations) but skips the entire build
toolchain — so it's far faster and never hits the pnpm build-approval failure.

> **Maintainers:** produce the release artifact with `bash infra/build-release.sh`
> on a machine that has Dart + Node + pnpm, then upload
> `dist/gisila-release-linux-<arch>.tar.gz` to a GitHub Release
> (`gh release create v<version> dist/gisila-release-linux-*.tar.gz`). Re-upload
> the same asset name to the newest release so `VERSION=latest` keeps working.

### Build from source

Prefer this only when you've changed the code and want to compile on the host.

### 1. Clone the repository

```bash
git clone https://github.com/your-org/gisila-panel.git /opt/gisila-panel
cd /opt/gisila-panel
```

### 2. Run the installer

```bash
sudo bash infra/install.sh
```

The installer is **idempotent** — safe to re-run after upgrades. It will:

1. Install system packages: PostgreSQL 16, Redis, Nginx, certbot, AppArmor, Dart SDK, build tools.
2. Create the `gisila` system user and `/srv/gisila/` directory layout.
3. Compile the API server (`gisila-panel`), background worker (`gisila-worker`), and privileged agent (`gisila-agent`) to native binaries and install them under `/usr/local/bin/`.
4. Drop a tightly-scoped `sudoers` rule so the `gisila` worker can invoke `gisila-agent` as root.
5. Install and enable systemd units for the API and worker.
6. Generate `/etc/gisila/.env` with a random `JWT_SECRET` and admin password (only on first run).
7. Write `/etc/gisila/database.yaml` and run the schema migration.
8. Install the Nginx panel vhost and reload Nginx.
9. Start `gisila-panel.service` and `gisila-worker.service`.

When complete you'll see:

```
✓ Gisila Panel installed successfully.

  API:    http://<server-ip>:8000
  Docs:   http://<server-ip>:8000/docs
  Admin:  http://<server-ip>:8000/admin

  Credentials are in /etc/gisila/.env (STUDIO_USERNAME / STUDIO_PASSWORD).
```

### 3. Point a domain and get TLS

```bash
# 1. Add a DNS A record: panel.your-domain.tld → <server-ip>
# 2. Update the Nginx server_name
sudo sed -i 's/panel\.example\.com/panel.your-domain.tld/' \
  /etc/nginx/sites-available/gisila-panel
sudo nginx -t && sudo systemctl reload nginx

# 3. Issue a Let's Encrypt certificate (auto-configures HTTPS redirect)
sudo certbot --nginx -d panel.your-domain.tld
```

---

## Webserver configuration

Gisila Panel ships a ready-to-use Nginx vhost at `infra/nginx-panel.conf`. The installer places it at `/etc/nginx/sites-available/gisila-panel` and symlinks it into `sites-enabled`.

### Default vhost (`infra/nginx-panel.conf`)

```nginx
# Managed by gisila-panel — vhost for the panel itself.
#
# Replace `panel.example.com` with your real hostname, then run:
#   certbot --nginx -d panel.example.com
# to get HTTPS + automatic renewal.

server {
    listen 80;
    listen [::]:80;
    server_name panel.example.com;

    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        # Required for WebSocket (live log streaming)
        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 75s;
    }

    client_max_body_size 50M;
    access_log /var/log/nginx/gisila-panel.access.log;
    error_log  /var/log/nginx/gisila-panel.error.log;
}
```

### After certbot — HTTPS vhost (auto-generated)

Certbot patches the vhost in place. The result looks like this:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name panel.your-domain.tld;

    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name panel.your-domain.tld;

    ssl_certificate     /etc/letsencrypt/live/panel.your-domain.tld/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/panel.your-domain.tld/privkey.pem;
    include             /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam         /etc/letsencrypt/ssl-dhparams.pem;

    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 75s;
    }

    client_max_body_size 50M;
    access_log /var/log/nginx/gisila-panel.access.log;
    error_log  /var/log/nginx/gisila-panel.error.log;
}
```

### Apache alternative

If you prefer Apache 2.4 instead of Nginx:

```apache
# /etc/apache2/sites-available/gisila-panel.conf

<VirtualHost *:80>
    ServerName panel.your-domain.tld

    # Let's Encrypt ACME challenge
    Alias /.well-known/acme-challenge/ /var/www/letsencrypt/.well-known/acme-challenge/
    <Directory /var/www/letsencrypt/>
        Options None
        AllowOverride None
        Require all granted
    </Directory>

    # Redirect everything else to HTTPS
    RewriteEngine On
    RewriteCond %{REQUEST_URI} !^/\.well-known/acme-challenge
    RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
</VirtualHost>

<VirtualHost *:443>
    ServerName panel.your-domain.tld

    SSLEngine on
    SSLCertificateFile    /etc/letsencrypt/live/panel.your-domain.tld/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/panel.your-domain.tld/privkey.pem

    ProxyPreserveHost On
    ProxyRequests     Off

    # WebSocket support (live log streaming)
    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} websocket [NC]
    RewriteRule ^/?(.*) ws://127.0.0.1:8000/$1 [P,L]
    RewriteRule ^/?(.*) http://127.0.0.1:8000/$1 [P,L]

    ProxyPass        / http://127.0.0.1:8000/
    ProxyPassReverse / http://127.0.0.1:8000/

    RequestHeader set X-Forwarded-Proto "https"

    LimitRequestBody 52428800   # 50 MB

    ErrorLog  ${APACHE_LOG_DIR}/gisila-panel.error.log
    CustomLog ${APACHE_LOG_DIR}/gisila-panel.access.log combined
</VirtualHost>
```

Enable it:

```bash
sudo a2enmod proxy proxy_http proxy_wstunnel rewrite ssl headers
sudo a2ensite gisila-panel
sudo apache2ctl configtest && sudo systemctl reload apache2
sudo certbot --apache -d panel.your-domain.tld
```

### Caddy alternative

```caddyfile
# /etc/caddy/Caddyfile

panel.your-domain.tld {
    reverse_proxy 127.0.0.1:8000 {
        header_up Host              {host}
        header_up X-Real-IP         {remote_host}
        header_up X-Forwarded-For   {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }

    # Caddy handles TLS and WebSockets automatically.
    log {
        output file /var/log/caddy/gisila-panel.log
    }
}
```

Caddy obtains and renews TLS certificates automatically — no certbot needed.

---

## Systemd services

Three systemd units are installed under `/etc/systemd/system/`:

| Unit | Binary | Purpose |
|------|--------|---------|
| `gisila-panel.service` | `/usr/local/bin/gisila-panel` | HTTP API server |
| `gisila-worker.service` | `/usr/local/bin/gisila-worker` | Background job/deployment worker |
| `gisila-apps.target` | — | Groups all user-app units for bulk start/stop |

Both services run as the `gisila` system user with strict systemd sandboxing (`NoNewPrivileges`, `ProtectSystem=strict`, `PrivateTmp`, etc.). The worker is allowed to call `gisila-agent` via a narrow `sudoers` rule.

### Useful service commands

```bash
# Status
sudo systemctl status gisila-panel gisila-worker

# Restart after config changes
sudo systemctl restart gisila-panel gisila-worker

# Follow live logs
journalctl -fu gisila-panel
journalctl -fu gisila-worker

# Follow logs for a hosted app
journalctl -fu gisila-app_<slug>
```

---

## Configuration

### `/etc/gisila/.env`

Generated by the installer on first run. Edit and restart the relevant service to apply changes.

| Variable | Default | Purpose |
|---|---|---|
| `PORT` | `8000` | API HTTP port. |
| `JWT_SECRET` | *(random)* | HMAC signing secret for JWTs. Rotate by editing + restarting. |
| `JWT_EXPIRE_DAYS` | `14` | Token lifetime in days. |
| `STUDIO_USERNAME` | `admin` | Username for the `/admin` panel. |
| `STUDIO_PASSWORD` | *(random)* | Password for the `/admin` panel. |
| `REDIS_HOST` | `127.0.0.1` | Redis hostname. |
| `REDIS_PORT` | `6379` | Redis port. |
| `APPS_ROOT` | `/srv/apps` | Root directory for per-app filesystems. |
| `APP_PORT_RANGE_MIN` | `4000` | Start of the internal port pool for user apps. |
| `APP_PORT_RANGE_MAX` | `4999` | End of the internal port pool for user apps. |
| `AGENT_BIN` | `/usr/local/bin/gisila-agent` | Path to the privileged agent binary. |
| `AGENT_MODE` | `sudo` | `sudo` for production; `dev` for Docker dev stack. |
| `NODE_ID` | `$(hostname -s)` | Identifier used in multi-node setups. |
| `NGINX_SITES_DIR` | `/etc/nginx/sites-enabled` | Where the agent writes per-app vhosts. |
| `SYSTEMD_UNITS_DIR` | `/etc/systemd/system` | Where the agent writes per-app unit files. |
| `APPARMOR_PROFILES_DIR` | `/etc/apparmor.d` | Where the agent writes per-app AppArmor profiles. |

### `/etc/gisila/database.yaml`

Points the API and worker at PostgreSQL. Both files are owned `gisila:gisila`, mode `0640`.

```yaml
default: default
connections:
  default:
    type: postgresql
    host: localhost
    port: 5432
    database: gisila_panel
    username: gisila
    password: gisila
    ssl: false
    connection_timeout: 30
    query_timeout: 30
    max_connections: 20
    min_connections: 2
```

---

## Updating

```bash
cd /opt/gisila-panel
git pull
sudo bash infra/install.sh   # idempotent — replaces binaries and re-runs migrations
```

## Uninstalling

```bash
sudo bash infra/uninstall.sh          # removes panel services; leaves hosted apps running
sudo bash infra/uninstall.sh --apps   # also removes every user app and /srv/apps
```

---

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Install guide](docs/INSTALL.md)
- [Database schema](docs/DATABASE.md)
- [API design](docs/API.md)
- [Security model](docs/SECURITY.md)
- [Deployment engine](docs/DEPLOYMENT_ENGINE.md)
- [Roadmap (MVP → production)](docs/ROADMAP.md)

## License

MIT.
