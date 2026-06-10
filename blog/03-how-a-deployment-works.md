---
title: "How a Deployment Works in Gisila Panel"
description: "From clicking Deploy to a running systemd service — a step-by-step walkthrough of the Gisila Panel deployment engine."
date: 2026-06-10
author: Gisila Team
tags: [deployment, architecture, systemd, tutorial]
---

# How a Deployment Works in Gisila Panel

You've created an app in Gisila Panel, wired up your git repository, and clicked **Deploy**. What happens next?

This post walks through the full deployment pipeline — from the API call to a running service behind Nginx with TLS — so you know exactly what the panel is doing on your server.

---

## The big picture

Gisila Panel uses a three-tier architecture for deployments:

```
You (browser)  →  Dart API  →  Redis queue  →  gisila-worker  →  gisila-agent  →  systemd
                     ↓                              ↓
                 Postgres                    Build logs → WebSocket → your browser
```

- **Dart API** — receives your deploy request, records state in Postgres, enqueues a job
- **Redis** — job queue for deployments, lifecycle actions, vhost updates, SSL issuance; pub/sub for live log streaming
- **gisila-worker** — background process that pops jobs and orchestrates the agent
- **gisila-agent** — privileged host-side binary (runs as root via sudo) that touches systemd, Nginx, AppArmor, and the filesystem
- **systemd** — actually runs your app as an isolated process

The API and worker run as the unprivileged `gisila` system user. The only privileged code path is `sudo /usr/local/bin/gisila-agent …`, gated by a tightly scoped sudoers rule.

---

## Step 1: You trigger a deployment

From the dashboard or API:

```http
POST /apps/{id}/deployments/
Content-Type: application/json
Authorization: Bearer <token>

{
  "sourceType": "git",
  "gitCommitSha": "abc123..."
}
```

Supported source types:

| Source | Description |
|--------|-------------|
| `git` | Clone or pull from a configured repository at a specific commit |
| `binary` | Upload a pre-compiled binary artifact |
| `zip` | Upload a ZIP archive of source code |

The `DeploymentsService` creates a new `Deployment` row with status `queued`, sets the app's status to `building`, and pushes a JSON payload onto the Redis list `gisila:queue:deployments`.

You immediately see the deployment appear in the UI with status **Queued**.

---

## Step 2: The worker picks up the job

`gisila-worker` runs continuously, blocking on `BLPOP gisila:queue:deployments`. When your job arrives, it deserializes the payload and calls `DeploymentWorker.onDeployment`.

The worker knows:

- Which app to deploy (ID, slug, runtime, build/start commands)
- Which source to use (git URL + commit, artifact path, or ZIP)
- Resource limits (memory, CPU, task count)
- Environment variables to inject

It then shells out to `gisila-agent` in sequence. Each subcommand's stdout/stderr is captured, persisted to `BuildLog` rows, and published on the Redis channel `gisila:logs:build:<deploymentId>`.

Your browser's **Logs** tab is a WebSocket subscribed to that channel — you see build output in real time, line by line.

---

## Step 3: Provision

```bash
gisila-agent provision \
  --user app_abc123 \
  --work-dir /srv/apps/app_abc123 \
  --env-file /srv/apps/app_abc123/shared/.env
```

This step is **idempotent** — safe to run on every deployment.

What it does:

1. Creates the Linux system user `app_abc123` if it doesn't exist (`useradd --system --no-create-home --shell /usr/sbin/nologin`)
2. Creates the directory layout:

   ```
   /srv/apps/app_abc123/
   ├── current/
   ├── releases/
   ├── shared/
   │   └── .env          ← your environment variables
   ├── tmp/
   └── logs/
   ```

3. Sets ownership and permissions (`0750`, owned by the app user)
4. Writes the `.env` file from the panel's env var store

If the user and directories already exist from a previous deployment, this step is a no-op.

---

## Step 4: Build

```bash
gisila-agent build \
  --user app_abc123 \
  --work-dir /srv/apps/app_abc123 \
  --runtime go \
  --source-type git \
  --git-url https://github.com/you/your-api.git \
  --git-commit abc123 \
  --build-command "go build -o bin/server ./cmd/server"
```

The build step depends on your runtime:

| Runtime | Build process |
|---------|--------------|
| `go` | `go build` with your build command |
| `rust` | `cargo build --release` |
| `dart` | `dart pub get` + `dart compile exe` |
| `node` / `bun` | `npm ci` or `bun install` |
| `python` | `pip install -r requirements.txt` |
| `zig` | `zig build` |
| `binary` | Copy uploaded artifact to release directory |
| `static` | Copy static files (HTML/CSS/JS) to release directory |

The output lands in `/srv/apps/app_abc123/releases/<timestamp>/`. A symlink at `current/` will point here once the deployment succeeds.

Build logs stream to your browser throughout this step. If the build fails, the deployment is marked **failed**, the app status reverts, and you see the error in the logs tab.

---

## Step 5: Apply systemd unit

```bash
gisila-agent apply-unit \
  --user app_abc123 \
  --work-dir /srv/apps/app_abc123 \
  --start-command "/srv/apps/app_abc123/current/bin/server" \
  --memory-max 256M \
  --cpu-quota 50% \
  --tasks-max 128 \
  --port 4127
```

The agent generates two files:

**Systemd unit** (`/etc/systemd/system/gisila-app_<slug>.service`):

```ini
[Unit]
Description=Gisila app: my-api
After=network.target

[Service]
Type=simple
User=app_abc123
Group=app_abc123
WorkingDirectory=/srv/apps/app_abc123/current
EnvironmentFile=/srv/apps/app_abc123/shared/.env
ExecStart=/srv/apps/app_abc123/current/bin/server
Restart=on-failure
RestartSec=5

# Resource limits
MemoryMax=256M
CPUQuota=50%
TasksMax=128

# Hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
RestrictNamespaces=true
MemoryDenyWriteExecute=true
LockPersonality=true
RestrictRealtime=true
ProtectKernelTunables=true
PrivateDevices=true
SystemCallArchitectures=native
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
ReadWritePaths=/srv/apps/app_abc123/shared /srv/apps/app_abc123/tmp /srv/apps/app_abc123/logs
ReadOnlyPaths=/srv/apps/app_abc123/current /srv/apps/app_abc123/releases

[Install]
WantedBy=gisila-apps.target
```

**AppArmor profile** (`/etc/apparmor.d/gisila-app_<slug>`):

A default-deny profile scoped to the app's work directory and runtime dependencies. Loaded with `apparmor_parser -r`.

Then: `systemctl daemon-reload`.

---

## Step 6: Apply Nginx vhost

```bash
gisila-agent apply-vhost \
  --hostname my-api.example.com \
  --port 4127 \
  --user app_abc123
```

The agent writes an Nginx server block:

```nginx
server {
    listen 80;
    server_name my-api.example.com;

    location / {
        proxy_pass http://127.0.0.1:4127;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Your app listens on `127.0.0.1:4127` — localhost only. Nginx is the public-facing entry point.

If you've configured a custom domain, a separate SSL job runs `certbot --nginx` to provision and install a Let's Encrypt certificate. Renewal is handled by certbot's standard cron — not by the panel.

Then: `nginx -t && systemctl reload nginx`.

---

## Step 7: Restart

```bash
gisila-agent restart --user app_abc123
```

Which runs:

```bash
systemctl restart gisila-app_<slug>
```

Your app starts. systemd manages the process lifecycle — if it crashes, `Restart=on-failure` brings it back after 5 seconds.

Logs go to journald:

```bash
journalctl -fu gisila-app_<slug>
```

The panel's **Logs** tab tails this stream via WebSocket when runtime log streaming is enabled.

---

## Step 8: Success

The worker marks the deployment as **active** (`isActive=true`), deactivates the previous deployment, sets the app status to **running**, and records an `AppEvent` in the audit log.

Your app is live at `https://my-api.example.com`.

The whole pipeline typically takes 30 seconds to 3 minutes depending on build time.

---

## What about rollbacks?

Every successful deployment keeps its release artifact in `/srv/apps/app_xxx/releases/<timestamp>/`. To roll back:

1. You select a previous deployment in the UI
2. The panel swaps the `current/` symlink to point at the old release
3. `gisila-agent restart` reloads the previous binary

No rebuild required. The old artifact is already on disk.

---

## Lifecycle operations

Beyond deploy, the panel supports:

| Action | What happens |
|--------|-------------|
| **Start** | `systemctl start gisila-app_<slug>` |
| **Stop** | `systemctl stop gisila-app_<slug>` |
| **Restart** | `systemctl restart gisila-app_<slug>` |
| **Console** | One-off command execution in the app's environment |
| **Scale limits** | Update `MemoryMax` / `CPUQuota` in the unit file and reload |

Each action goes through the same Redis queue → worker → agent pipeline.

---

## Monitoring

The **Metrics** tab samples CPU and RAM directly from cgroups v2:

- `/sys/fs/cgroup/.../memory.current` — current memory usage
- `/sys/fs/cgroup/.../cpu.stat` — CPU time consumed

No Prometheus required. No sidecar containers. The panel reads kernel accounting files directly.

Graphs update on a polling interval and show usage against your configured limits.

---

## Multi-app on one node

Every app on your VPS goes through this same pipeline independently:

```
/srv/apps/
├── app_abc123/    → gisila-app_my-api.service     → :4127 → my-api.example.com
├── app_def456/    → gisila-app_webhook.service    → :4128 → hooks.example.com
├── app_ghi789/    → gisila-app_worker.service     → :4129 → (internal only)
└── app_jkl012/    → gisila-app_dashboard.service  → :4130 → dash.example.com
```

Each app has its own Linux user, systemd unit, AppArmor profile, port, and Nginx vhost. They share nothing except the host kernel and the Nginx edge.

Port allocation is managed automatically from a configurable range (default: 4000–4999).

---

## Try it yourself

The fastest way to see this pipeline in action:

```bash
git clone https://github.com/your-org/gisila-panel.git
cd gisila-panel
docker compose up
```

Open `http://localhost:3000`, create an account, add an app, and deploy. In dev mode (`AGENT_MODE=dev`), the worker logs the commands it *would* send to `gisila-agent` without touching systemd — so you can trace the full flow safely.

For a real end-to-end test, install on an Ubuntu VPS:

```bash
sudo bash infra/install.sh
```

Then deploy a simple Go or Python HTTP server and watch the logs stream in.

---

## Further reading

- [Architecture](../docs/ARCHITECTURE.md) — full system design
- [Deployment engine](../docs/DEPLOYMENT_ENGINE.md) — agent subcommands and runtime matrix
- [Security model](../docs/SECURITY.md) — isolation guarantees in detail
- [API reference](../docs/API.md) — REST endpoints for CI/CD integration

---

**Previous:** [← Why We Skipped Docker](./02-why-we-skipped-docker.md)
