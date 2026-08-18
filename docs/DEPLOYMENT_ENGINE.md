# Deployment engine

## Overview

The deployment engine is a **Dart CLI** (`gisila-agent`) running as root
on the host, plus an **idempotent worker** (`gisila-worker`) that reads
jobs from Redis and shells out to the agent over sudo.

Every step is idempotent — re-running it is safe and converges towards
the declared state. This is what makes rollbacks cheap and what lets the
worker survive crashes mid-deployment.

## Queue topology

Redis lists used as work queues:

| Queue | Producer | Consumer | Payload |
|---|---|---|---|
| `gisila:queue:deployments` | `DeploymentsService.trigger` | worker | `{deploymentId, appId, sourceType, gitCommitSha?, artifactPath?}` |
| `gisila:queue:lifecycle` | `LifecycleService.{start,stop,restart}` | worker | `{appId, action}` |
| `gisila:queue:vhosts` | `DomainsService` | worker | `{appId, reason}` |
| `gisila:queue:ssl` | `DomainsService.issueCert` | worker | `{appId, domainId, hostname}` |
| `gisila:queue:network` | `AppsService.setNetworkExposure` | worker (`onNetworkExposure`) | `{appId, reason: 'expose'\|'unexpose'}` — reconciles the host firewall for a `tcp` app's port, no rebuild |
| `gisila:queue:applications` | `ApplicationService.{install,remove}` | `ApplicationWorker` | `{action, applicationId, version?, applicationVersionId?, dropFamily?}` |

Redis pubsub channels for live logs:

| Channel | Publisher | Subscriber |
|---|---|---|
| `gisila:logs:build:<deploymentId>` | worker | UI (WebSocket) |
| `gisila:logs:runtime:<appId>` | (future) journald tailer | UI (WebSocket) |

## Deployment lifecycle

```
created ──▶ queued ──▶ building ──▶ deploying ──▶ succeeded
                                                  └── failed
                                                  └── rolled_back
```

1. `queued` — row inserted, message on the queue.
2. `building` — worker picked it up, agent is provisioning + compiling.
3. `deploying` — artifact ready, `apply-unit` + restart, plus (depending on
   `App.exposeMode`) either `apply-vhost` (`web`) or `expose-port`/
   `unexpose-port` (`tcp`; `internal` gets neither — see [Network exposure
   modes](#network-exposure-modes)).
4. `succeeded` — `App.status='running'`, `Deployment.isActive=true`,
   all previous deployments for this app have `isActive=false`.
5. `failed` — `App.status='failed'`, `failureReason` captured.
6. `rolled_back` — caller invoked `POST …/rollback`; a fresh deployment
   row is queued that points at the same `artifactPath`.

## Agent subcommands

| Subcommand | What it does | Idempotent? |
|---|---|---|
| `provision` | Ensure Linux user + work-dir layout + `.env` file | ✓ |
| `build` | Fetch source (git / zip / binary) and dispatch to the app's `RuntimePlugin.build()` via `--deploy-mode` | ✓ (per artifact) |
| `apply-unit` | Render + write `gisila-<user>.service` and AppArmor profile, reload systemd. `--expose-mode` (`web`\|`tcp`\|`internal`) raises `LimitNOFILE` (see [Network exposure modes](#network-exposure-modes)) | ✓ |
| `apply-vhost` | Render + write nginx vhost, `nginx -t`, reload | ✓ |
| `expose-port` / `unexpose-port` | `ufw allow`/`ufw delete allow <port>/tcp` — opens/closes the host firewall for a `tcp` app's port (no nginx involved) | ✓ |
| `issue-cert` | `certbot --nginx -d <host>` + reload nginx | ✓ (skip if cert exists & valid) |
| `start` / `stop` / `restart` | `systemctl <action> gisila-<user>.service` | ✓ |
| `uninstall` | Stop + disable unit, drop unit / profile / vhost | ✓ |
| `runtime install --key <k> [--version <v>]` | Dispatch to `RuntimePlugin.installToolchain()` (pyenv/fnm/SDK setup). Versioned runtimes reject a missing `--version` rather than succeeding without installing anything | ✓ |
| `runtime remove --key <k> [--version <v>]` | Dispatch to `RuntimePlugin.removeToolchain()`. With `--version`, removes only that one | ✓ |
| `runtime status --key <k>` | Report `{versioned, versions[], installed}` — the versions actually on disk, not what the panel believes | ✓ |

## Runtime plugin table

Runtime support is no longer a hand-written `switch (runtime)` — each row
below is an independent `RuntimePlugin` (`agent/lib/runtimes/`), registered
in `RuntimeRegistry` and backed by an `Application` catalog entry
(`backend/lib/services/application_catalog.dart`). Adding a new runtime
means adding a new plugin + catalog entry, not editing this table's
implementation.

| Runtime | Plugin | Supported deploy modes | Default build command | Default start command |
|---|---|---|---|---|
| dart | `DartPlugin` | `build_execute` | `mkdir -p build && dart pub get && dart compile exe bin/server.dart -o build/app` | `<work-dir>/current/app` |
| go | `GoPlugin` | `build_execute` | `go build -o build/app ./...` | `<work-dir>/current/app` |
| rust | `RustPlugin` | `build_execute` | `cargo build --release` | as specified by user |
| node | `NodePlugin` | `build_execute` | `npm ci` | `node dist/index.js` |
| bun | `BunPlugin` | `build_execute` | `bun install` | `bun run start` |
| celery | `CeleryPlugin` | `build_execute` | `python3 -m venv .venv && .venv/bin/pip install -r requirements.txt` | `.venv/bin/celery …` |
| python | `PythonPlugin` | `direct_run` | (none — deps only) `python3 -m venv .venv && .venv/bin/pip install -r requirements.txt` | `.venv/bin/python …` |
| binary | `BinaryPlugin` | `direct_run` | (none — drop in place) | `<work-dir>/current/app` |
| zig | `ZigPlugin` | `build_execute` | as specified | as specified |
| static | `StaticPlugin` | `static_publish` | (none — nginx serves files) | n/a (no process) |

Modes are declared per-Application (`deploy_modes`) and enforced per-App
(`App.deployment_mode`, validated against its Application's supported
modes); `build_execute` compiles/packages before running the artifact,
`direct_run` runs the interpreter/pre-built binary against the source in
place, and `static_publish` skips the process entirely.

### Multiple versions side by side

`dart`, `go`, `rust`, `node`, `bun` and `python` are **versioned**: several
toolchain versions can be installed at once, so one app can pin Python 3.11
while another runs 3.13. Each installed version is an `ApplicationVersion`
row hanging off the `Application`, and one of them is marked default for
apps that don't pin a version themselves. `celery` is not versioned in its
own right — it runs on whichever Python its app pins — and `zig`, `static`
and `binary` have no toolchain to install.

On disk this was always possible: pyenv, fnm and rustup are version managers,
and Dart/Go/Bun install under a per-version prefix
(`/opt/dart-versions/<v>`, …). What changed is that the panel now models it
instead of assuming one version per runtime.

Removing a version is refused while any app still pins it. Removing the
default promotes another installed version in its place.

The build is always run as the **app's** Linux user via `runuser -u`, so
even a compromised build step can only touch the app's own work-dir.

## Network exposure modes

`App.exposeMode` (`web` | `tcp` | `internal`, set at creation, immutable
afterward) determines which network-facing step runs during a deployment
instead of `apply-vhost`:

- **`web`** (default) — unchanged from above: `apply-vhost` renders the
  nginx reverse proxy (+ optional `issue-cert` once a Domain is attached).
- **`tcp`** — no nginx, no domain. The app must bind `0.0.0.0:<internalPort>`
  itself (nothing proxies to it). After `apply-unit`/`restart`, the worker
  calls `expose-port --port <internalPort>` if `App.publiclyReachable` or
  `unexpose-port` otherwise — this is the exact same `ufw allow`/`ufw delete
  allow` mechanism `PostgresService`/`MongoService` already use for public
  database access, just applied to an app's own port instead of a database
  port. Flipping `publiclyReachable` later (`POST /apps/{id}/network`)
  re-runs just this step via `gisila:queue:network`, without a redeploy.

  **File descriptors.** A `web` app never holds more than a handful of
  sockets open — Nginx terminates every client connection and pools a small,
  bounded number of upstream connections to the app regardless of how many
  clients it's serving. A `tcp` (or `internal`) app has no such multiplexer:
  every client connection is a raw socket, and therefore a file descriptor,
  held by the app process itself. `apply-unit` takes `--expose-mode`
  precisely for this — `SystemdUnit` raises `LimitNOFILE` from `4096` to
  `65536` whenever `exposeMode != 'web'`, mirroring the same distinction
  already made for direct-socket services like MongoDB (`LimitNOFILE=64000`)
  and MinIO (`65536`) vs. nginx-proxied ones like pgAdmin (`4096`).
- **`internal`** — no nginx, no domain, no firewall rule ever opened. The app
  is reachable only via `127.0.0.1:<internalPort>` from other local
  processes (e.g. a sidecar/worker fronted by a `web` app on the same host).

`DomainsService.add` rejects attaching a Domain to a `tcp`/`internal` app
(422) since there is no vhost for a hostname to point at. Teardown
(`_destroyApp`) always runs `unexpose-port` first for a `tcp` app so the
firewall hole never outlives the app.

**Never locking out SSH.** `expose-port`/`unexpose-port` are thin wrappers
around [`Priv.ufwAllow`/`Priv.ufwDeny`](../agent/lib/runtime/priv.dart) — the
same helpers `PostgresService`/`MongoService` public exposure already use
(the Postgres agent code has its own `_ufwAllow`/`_ufwDeny`, but they now just
delegate to `Priv`'s, so this applies there too). Opening a port
(`ufwAllow`) can never lock anyone out, but *closing* one (`ufwDeny`) can —
if it happens to be the port an operator is SSH'd in on, and ufw's default
incoming policy is deny, removing that rule cuts off remote access with no
way back in short of console/rescue access. `Priv.ufwDeny` guards against
this unconditionally: it refuses to touch a port matching `22` or any `Port`
directive it finds in `/etc/ssh/sshd_config`/`sshd_config.d/*.conf` (many
hardened hosts move SSH off 22, which alone would sail past every caller's
own `port >= 1024` validation). Neither this feature nor any existing caller
ever runs `ufw enable`/`ufw --force enable`/`ufw default …`/`ufw reset` — the
panel only ever adds or removes single `allow <port>/tcp` rules on a
firewall the operator chose to enable themselves.

## Filesystem layout per app

```
/srv/apps/app_xxx/
├── .env                  # managed env file (mode 0640, owner app_xxx)
├── current/              # symlink-like read-only payload (the live artifact)
│   └── app               # the executable
├── releases/
│   ├── current_build/    # most recent source checkout
│   └── 2026-05-27-093000/  # archived release dirs (rotated)
├── shared/               # persistent rw scratch (databases, uploads…)
├── tmp/                  # ephemeral rw scratch
└── logs/                 # optional rw log dir
```

`current/` and `releases/` are mounted read-only by the systemd unit;
`shared/`, `tmp/` and `logs/` are the only places the app can write.

## Generated artifacts

### systemd unit (see [`agent/lib/generators/systemd_unit.dart`](../agent/lib/generators/systemd_unit.dart))

```ini
[Unit]
Description=Gisila app app_xxx (id=12)
After=network.target
PartOf=gisila-apps.target

[Service]
Type=simple
User=app_xxx
WorkingDirectory=/srv/apps/app_xxx/current
ExecStart=/srv/apps/app_xxx/current/app
Restart=always
EnvironmentFile=/srv/apps/app_xxx/.env
Environment=PORT=4001
NoNewPrivileges=true
ProtectSystem=strict
PrivateTmp=true
ProtectHome=true
MemoryMax=256M
CPUQuota=50%
TasksMax=100
RestrictNamespaces=true
MemoryDenyWriteExecute=true
LockPersonality=true
AppArmorProfile=gisila-app_xxx
…
```

### nginx vhost (see [`agent/lib/generators/nginx_vhost.dart`](../agent/lib/generators/nginx_vhost.dart))

```nginx
server {
  listen 80;
  server_name api.example.com;
  location / {
    proxy_pass http://127.0.0.1:4001;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Real-IP $remote_addr;
  }
}
```

### AppArmor profile (see [`agent/lib/generators/apparmor_profile.dart`](../agent/lib/generators/apparmor_profile.dart))

Default-deny outside `/srv/apps/<user>/`, `/tmp/`, and the runtime's
standard libraries.
