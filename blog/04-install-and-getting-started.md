---
title: "Install Gisila Panel and Get Your First App Live"
description: "A practical walkthrough: stand up Gisila Panel on a VPS, create an account, deploy your first app, attach a domain, and handle day-two operations."
date: 2026-08-13
author: Gisila Team
tags: [install, getting-started, tutorial, self-hosting, paas]
---

# Install Gisila Panel and Get Your First App Live

The first three posts covered *why* Gisila Panel exists, why it skips Docker, and what happens when you click Deploy. This one is the practical companion: **get a panel running on a VPS, ship a real app, and know what to do next.**

By the end you will have:

- A production panel on Ubuntu or Debian
- An HTTPS dashboard
- A first app running as a systemd service behind Nginx
- A custom domain with Let's Encrypt
- The day-two habits: logs, env vars, updates, backups of config

If you only want the commands, skip to [Install in five minutes](#install-in-five-minutes). If you want the whole path from empty VPS to a live API, keep reading.

---

## What you need

Gisila Panel is a **single-node PaaS**. It runs on one Linux box and hosts many apps on that box. You bring the machine; the installer brings the control plane.

| Requirement | Details |
|-------------|---------|
| OS | Ubuntu 22.04+ or Debian 12+ (x64 or arm64) |
| Access | A user with `sudo` (or root) |
| Ports | 80 and 443 open |
| Domain | A hostname pointed at the server (for TLS) |
| Database | PostgreSQL 16+ (**not** installed by the panel) |
| Queue | Redis 7+ (**not** installed by the panel) |
| RAM | 1 GB is enough for the panel + a handful of small apps; 2–4 GB is more comfortable |

The panel is a *client* of Postgres and Redis, not their operator. They can live on the same host or on a managed instance elsewhere. That split is intentional: you can point at RDS / a Hetzner managed DB / a Redis elsewhere without the installer taking over those services.

A $5–20/month VPS from Hetzner, DigitalOcean, Linode, or similar is the intended home. See [Why We Skipped Docker](./02-why-we-skipped-docker.md) for why a small box can still hold dozens of apps.

---

## Install in five minutes

### 1. Postgres and Redis (same host)

Skip this if you already have them. The defaults below match the installer exactly, so you will not need extra env vars.

```bash
sudo apt-get update
sudo apt-get install -y postgresql redis-server
sudo systemctl enable --now postgresql redis-server

sudo -u postgres psql -c "CREATE ROLE gisila LOGIN PASSWORD 'gisila';"
sudo -u postgres createdb --owner=gisila gisila_panel
```

For anything facing the internet, use a stronger password and pass it to the installer with `DATABASE_URL` / `REDIS_URL`.

### 2. Prebuilt install (recommended)

No Dart SDK, no Node.js, no pnpm. The script downloads compiled binaries and the panel UI from a GitHub Release, then wires systemd + Nginx.

```bash
curl -fsSL https://raw.githubusercontent.com/gumisofts/gisila_panel/main/infra/install-prebuilt.sh \
  | sudo env \
      PANEL_DOMAIN=panel.example.com \
      ISSUE_TLS=1 \
      bash
```

Replace `panel.example.com` with a DNS A record that already points at this box. `ISSUE_TLS=1` runs certbot so you land on HTTPS immediately.

If Postgres or Redis is remote:

```bash
curl -fsSL https://raw.githubusercontent.com/gumisofts/gisila_panel/main/infra/install-prebuilt.sh \
  | sudo env \
      DATABASE_URL='postgresql://gisila:secret@10.0.0.5:5432/gisila_panel' \
      REDIS_URL='redis://:secret@10.0.0.5:6379' \
      PANEL_DOMAIN=panel.example.com \
      ISSUE_TLS=1 \
      bash
```

Pin a release with `VERSION=0.1.0` if you do not want `latest`.

When the script finishes:

```
✓ Gisila Panel installed successfully.
  Panel:  https://panel.example.com
  Docs:   https://panel.example.com/docs
  Admin:  https://panel.example.com/admin
```

The installer is **idempotent**: re-run it after upgrades. It will:

1. Install Nginx, certbot, AppArmor, and the `psql` client (not Postgres/Redis themselves)
2. Check that Postgres and Redis are reachable, and fail fast if not
3. Create the `gisila` system user and `/srv/gisila/`, `/srv/apps/` layout
4. Install `gisila-panel`, `gisila-worker`, and `gisila-agent`
5. Enable systemd units for the API and worker
6. Write `/etc/gisila/.env` (random `JWT_SECRET` and admin password on first run) and run migrations
7. Install the panel Nginx vhost and start everything

### 3. First login

Open the panel URL and **register an account**. Registration is public: it creates your user, a default team, and a JWT. That account is the one you use every day.

Gisila Studio at `/admin` is a separate admin UI. Credentials are in `/etc/gisila/.env` as `STUDIO_USERNAME` / `STUDIO_PASSWORD`. Use it for low-level inspection; use the dashboard for deploying apps.

```bash
sudo grep STUDIO_ /etc/gisila/.env
```

---

## What just got installed

Three processes, three jobs:

| Unit | Runs as | Role |
|------|---------|------|
| `gisila-panel.service` | `gisila` | HTTP API + dashboard backend |
| `gisila-worker.service` | `root` | Picks jobs off Redis and calls the agent |
| `gisila-agent` | invoked by the worker | Privileged host work: users, systemd, Nginx, AppArmor, certbot |

Your apps will live under `/srv/apps/` as isolated Linux users. The panel itself listens on `127.0.0.1:8000`; Nginx is the public edge.

Useful checks right after install:

```bash
sudo systemctl status gisila-panel gisila-worker
journalctl -fu gisila-panel
journalctl -fu gisila-worker
```

---

## Getting started: your first app

The mental model is **Team → Project → App**. Registration already created a team. Create a project (or let the new-app flow create one), then create an app.

### Create an app

In the dashboard: **Apps → New app**.

You will pick:

| Field | What to put |
|-------|-------------|
| **Name** | A slug you will recognize (`hello-api`) |
| **Runtime** | `go`, `dart`, `rust`, `node`, `bun`, `python`, `zig`, `celery`, `static`, or `binary` |
| **Source** | Git URL, uploaded ZIP, or a pre-built binary |
| **Build / start commands** | Leave blank to use runtime defaults, or override |
| **Resource limits** | Memory, CPU quota, task cap. Start small |

Supported runtimes and their defaults:

| Runtime | Typical build | Typical start |
|---------|---------------|---------------|
| Go | `go build -o build/app ./...` | the compiled binary |
| Dart | `dart pub get` + `dart compile exe` | the compiled binary |
| Rust | `cargo build --release` | as you specify |
| Node | `npm ci` | `node dist/index.js` |
| Bun | `bun install` | `bun run start` |
| Python | venv + `pip install -r requirements.txt` | interpreter / gunicorn |
| Static | copy files | Nginx serves them (no process) |
| Binary | none | drop in the uploaded artifact |

Runtimes like Node, Python, Dart, and Go are **versioned**: you can pin Python 3.11 on one app and 3.13 on another. Install the toolchain from the **Applications** catalog in the UI before the first deploy if the version you want is not already on the box.

### A tiny Go API that works first try

Your app must listen on the port Gisila injects as `PORT` (localhost only). Nginx proxies the public hostname to that port.

```go
package main

import (
	"fmt"
	"net/http"
	"os"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "hello from gisila")
	})
	http.ListenAndServe("127.0.0.1:"+port, nil)
}
```

Point the app at the git repo, click **Deploy**, and watch the **Logs** tab. Build output streams over WebSocket as `gisila-agent` clones, compiles, writes a systemd unit, writes an Nginx vhost, and restarts the service.

A typical first deploy takes 30 seconds to a few minutes depending on compile time. When status flips to **running**, the app is live on its assigned internal port.

For the full pipeline (provision → build → unit → vhost → restart), see [How a Deployment Works](./03-how-a-deployment-works.md).

### Environment variables

On the app's **Env** tab, add `KEY=value` pairs. Mark secrets so the UI hides the value. They land in the app's `.env` file and are injected by systemd via `EnvironmentFile`. Redeploy or restart after changing them so the process picks them up.

### Custom domain and TLS

1. Add a DNS A (or AAAA) record: `api.example.com → <server-ip>`
2. On the app's **Domains** tab, add `api.example.com`
3. Issue a certificate: the panel queues `certbot --nginx` for that hostname

The app still listens only on `127.0.0.1:<assigned-port>`. Nginx is the only public listener. Certbot's usual renewal timer keeps the cert alive; the panel does not reinvent that.

---

## The rest of the panel

Once the first app is up, these are the pieces you will actually use.

### Lifecycle

Start, stop, and restart from the app overview. Each action is a Redis job, not a raw `systemctl` from the UI. Rollback points `current/` at a previous release artifact and restarts. No rebuild if the binary is still on disk.

### Logs and metrics

- **Build logs**: live during deploy, persisted afterwards
- **Runtime logs**: `journalctl -fu gisila-app_<slug>` on the host; the UI tails the same stream when runtime streaming is enabled
- **Metrics**: CPU and RAM sampled from cgroups v2, plotted against the limits you set

No Prometheus sidecar required for the MVP graphs.

### Teams, projects, and roles

Invite people by email. Roles are `owner`, `admin`, `developer`, and `viewer`. Apps belong to a project; projects belong to a team. Use this from day one even if you are solo. It matches how the API is structured.

### API tokens and CI

Settings → Tokens issues a personal token (`gsl_…`). Use it as:

```http
Authorization: Bearer gsl_…
```

or

```http
X-API-Token: gsl_…
```

Swagger lives at `/docs`. A deploy from CI is:

```http
POST /apps/{id}/deployments/
Content-Type: application/json
Authorization: Bearer gsl_…

{"sourceType": "git", "gitCommitSha": "abc123"}
```

SSH keys and git deploy keys live under Settings as well, for private repositories.

### Managed extras

The dashboard also covers:

- **PostgreSQL instances** (versions 14–18) for apps that need a database
- **Managed services** such as Redis, Memcached, SMTP, Mailpit
- **Mail hosting** (Postfix + Dovecot, DKIM/DMARC DNS)
- **App console** for one-off commands in the app's environment

Treat these as optional. The core loop is still: create app → deploy → attach domain.

### Studio admin

`/admin` (Gisila Studio) is the operator console: inspect models, tweak catalog entries, debug when the pretty UI is not enough. Keep `STUDIO_PASSWORD` out of git and rotate it in `/etc/gisila/.env` if it ever leaks.

---

## Configuration you will actually edit

`/etc/gisila/.env` controls the control plane. After edits:

```bash
sudo systemctl restart gisila-panel gisila-worker
```

| Variable | Why it matters |
|----------|----------------|
| `JWT_SECRET` | Signs session tokens. Rotate + restart if leaked. |
| `STUDIO_USERNAME` / `STUDIO_PASSWORD` | `/admin` login |
| `REDIS_HOST` / `REDIS_PORT` / `REDIS_PASSWORD` | Job queue |
| `PANEL_DOMAIN` | Hostname on the panel vhost |
| `APPS_ROOT` | Default `/srv/apps` |
| `APP_PORT_RANGE_MIN` / `MAX` | Internal port pool (default 4000–4999) |
| `NODE_ID` | Identity when you later add more hosts |

PostgreSQL is in `/etc/gisila/database.yaml`, usually written from `DATABASE_URL` at install time. Both files are `gisila:gisila`, mode `0640`.

---

## Domain for the panel itself (if you skipped it at install)

```bash
# DNS: panel.your-domain.tld → this server

sudo sed -i 's/panel\.example\.com/panel.your-domain.tld/' \
  /etc/nginx/sites-available/gisila-panel
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d panel.your-domain.tld
```

---

## Updating

Prebuilt install: re-run the same script:

```bash
curl -fsSL https://raw.githubusercontent.com/gumisofts/gisila_panel/main/infra/install-prebuilt.sh \
  | sudo bash
```

Or pin: `sudo VERSION=x.y.z bash infra/install-prebuilt.sh`.

Source install:

```bash
cd /opt/gisila-panel
git pull
sudo bash infra/install.sh
```

Hosted apps keep running. The installer replaces panel binaries atomically and re-runs migrations.

---

## Uninstall

```bash
sudo bash infra/uninstall.sh          # control plane only
sudo bash infra/uninstall.sh --apps   # also remove every user app and /srv/apps
sudo bash infra/uninstall.sh --purge  # also drop the gisila_panel DB/role + gisila:* Redis keys
sudo bash infra/uninstall.sh --all    # apps + purge
```

`--purge` only works when Postgres/Redis are local (`sudo -u postgres` / local `redis-cli`). On a managed instance, drop the database and `gisila:*` keys yourself.

---

## Build from source (optional)

Use this when you have patched the code and want to compile on the host. You need the Dart SDK (and Node + pnpm if you also pass `BUILD_FRONTEND=1`).

```bash
git clone https://github.com/gumisofts/gisila_panel.git /opt/gisila-panel
cd /opt/gisila-panel
sudo DATABASE_URL='postgresql://gisila:secret@127.0.0.1:5432/gisila_panel' \
     REDIS_URL='redis://127.0.0.1:6379' \
     PANEL_DOMAIN=panel.example.com \
     bash infra/install.sh
```

Same knobs as the prebuilt installer. Prefer prebuilt on a production VPS.

---

## Local development (Docker)

To explore the UI without a VPS:

```bash
git clone https://github.com/gumisofts/gisila_panel.git
cd gisila_panel
docker compose up
```

| Service | URL |
|---------|-----|
| Dashboard | http://localhost:3000 |
| API | http://localhost:8000 |
| Swagger | http://localhost:8000/docs |
| Studio | http://localhost:8000/admin (`admin` / `admin`) |

In compose, `AGENT_MODE=dev`: the worker **logs** the agent commands it would run and does not touch systemd, Nginx, or AppArmor. Real deploys need a real Ubuntu/Debian host.

---

## If something goes wrong

**Installer cannot reach Postgres or Redis.** The script fails fast on purpose. Confirm `pg_isready` / `redis-cli ping`, firewall rules, and that `DATABASE_URL` / `REDIS_URL` match reality.

**Panel is up, apps never leave "queued".** `gisila-worker` is down or Redis is the wrong instance. `journalctl -fu gisila-worker` is the first place to look.

**Deploy fails at build.** Open the deployment logs in the UI. Missing toolchain (Go/Node/Python version not installed) is the usual cause. Install it from **Applications**, then redeploy.

**TLS fails.** DNS must already point at this box, ports 80/443 must be open, and `PANEL_DOMAIN` / the app hostname must match the cert request. Certbot talks to Let's Encrypt over HTTP-01.

**App is running but 502.** The process is not listening on `PORT`, or it bound `0.0.0.0` vs the expected localhost port. Gisila injects `PORT`; your server should use it and bind `127.0.0.1`.

---

## What to read next

You now have a panel, a first app, and the operator habits. Deeper docs:

- [Install guide](../docs/INSTALL.md): every installer flag
- [Architecture](../docs/ARCHITECTURE.md): control plane vs agent
- [Deployment engine](../docs/DEPLOYMENT_ENGINE.md): runtimes, queues, filesystem layout
- [Security model](../docs/SECURITY.md): users, AppArmor, cgroups, seccomp
- [API reference](../docs/API.md): REST + WebSocket map
- [Roadmap](../docs/ROADMAP.md): webhooks, multi-node, optional Docker

---

**Previous:** [← How a Deployment Works](./03-how-a-deployment-works.md)

**Next:** [Set Up Your Own Mail Server →](./05-setup-your-own-mail-server.md)
