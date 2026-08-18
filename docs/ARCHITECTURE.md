# Architecture

## Goals

- Native Linux execution — every user app is a plain `systemd` service.
- Multi-tenant on a single small VPS — per-user Linux accounts +
  `cgroups v2` + `AppArmor` + `seccomp` (via systemd).
- API-first control plane that doubles as a UI server.
- Pluggable agents — today there's a single privileged host-side agent;
  tomorrow we can add an SSH-based remote agent or a Docker isolation
  agent without touching the API.

## Components

```
┌───────────────────────────┐
│        Next.js UI         │  React 19 / App Router
└──────────────┬────────────┘
               │ HTTPS, JWT bearer or `gsl_…` API token
┌──────────────▼────────────┐
│   Dart API (gisila stack) │  Shelf + gisila + gisila_doc + gisila_orm
│   - /auth, /teams, /apps  │
│   - /apps/{id}/deployments│
│   - /apps/{id}/domains    │
│   - /me/security/*        │
│   - /admin   (Studio)     │
│   - /docs    (Swagger)    │
│   - /ws/*    (WebSockets) │
└──┬──────────┬─────────────┘
   │ pg       │ redis
   ▼          ▼
 Postgres   Redis  ←──── pubsub: logs · queues: deployments/lifecycle/vhosts/ssl/network
                            │
                            ▼
                ┌───────────────────────┐
                │ gisila-worker (Dart)  │ blocking BLPOP on queues
                │ shells out via sudo   │
                └──────────┬────────────┘
                           │
                           ▼
                ┌───────────────────────┐
                │  gisila-agent (root)  │ provision · build · apply-* · cert
                └──────────┬────────────┘
                           │
                           ▼
        systemd  ·  nginx  ·  apparmor  ·  cgroups v2  ·  certbot
```

## Data flow — a deployment

1. UI calls `POST /apps/{id}/deployments/` (JSON body
   `{sourceType, gitCommitSha?, artifactId?}`).
2. `DeploymentsService.trigger` inserts a `Deployment(queued)` row, marks the
   `App.status='building'`, and pushes a JSON payload onto the Redis list
   `gisila:queue:deployments`.
3. `gisila-worker` is sitting in `BLPOP`; it pops the message and calls
   `DeploymentWorker.onDeployment`.
4. The worker shells out to `gisila-agent`:
   - `provision` (idempotent: useradd + dir layout + .env file)
   - `build` (git clone / unzip / install binary, then dispatches to the
     app's `RuntimePlugin` — see [Application Management](#application-management)
     below — passing `--deploy-mode build_execute|direct_run|static_publish`)
   - `apply-unit` (write AppArmor profile, write systemd unit, reload)
   - `apply-vhost` (write nginx vhost, reload)
   - `restart` (systemctl restart gisila-app_xxx)
5. Stdout/stderr from the agent is streamed back to the worker, persisted
   into `BuildLog`, and `PUBLISH`ed on `gisila:logs:build:<deploymentId>`.
6. The UI's logs tab is a WebSocket bridged to that Redis channel.
7. On success the worker flips the `Deployment.isActive=true`, switches the
   `App.status='running'`, and records an `AppEvent`.

## Application Management

Runtime/language support (Python, Dart, Node, …) is **not** hardcoded into
the panel or bundled with its installation — it's modeled as its own
independently-managed entity, `Application`, decoupled from both the panel's
release cycle and from any specific deployed `App`:

```
┌─────────────────────────────┐        ┌───────────────────────────────┐
│ Application catalog (builtin) │      │ apps table                     │
│ backend/lib/services/         │      │  application_id → applications │
│ application_catalog.dart      │      │  deployment_mode                │
└──────────────┬────────────────┘      └───────────────┬─────────────────┘
               │ install/update/remove                  │ deploy job
               ▼                                        ▼
     applications table (per host,          ┌────────────────────────────┐
     status: pending|installing|            │ RuntimeRegistry (agent)     │
     installed|updating|removing|failed)    │  key → RuntimePlugin        │
               │                             │  DartPlugin · PythonPlugin  │
               ▼                             │  NodePlugin · … (one per     │
     gisila:queue:applications                │  builtin runtime)            │
     → ApplicationWorker →                    └────────────────────────────┘
     `gisila-agent runtime install|remove --key <k> [--version <v>]`
```

- **Catalog vs. installed state.** `kApplicationCatalog` (in-repo, one
  `ApplicationDef` per builtin runtime) is the set of Applications the panel
  *knows how to* support. The `applications` table is the per-host
  *installed* state — mirroring the existing `ManagedService` /
  `PostgresInstance` pattern (`GET /applications/catalog` vs. `GET
  /applications/`, `ApplicationService`, `ApplicationWorker`).
- **Deployment modes.** Each Application declares which of
  `build_execute` (compile/package, then run the artifact), `direct_run`
  (interpreter/pre-built binary runs the source in place, no compile step),
  or `static_publish` (nginx serves files directly, no process) it supports.
  An `App` picks one via `deployment_mode`, validated against its
  Application's supported modes.
- **RuntimePlugin.** On the agent side, `RuntimeRegistry` (a `key →
  RuntimePlugin` map in `agent/lib/runtime/runtime_registry.dart`) replaces
  what used to be a single hand-written `switch (runtime)` in
  `gisila-agent.dart`. Each plugin (`agent/lib/runtimes/<key>/…`) owns its
  toolchain install/remove (`installToolchain`/`removeToolchain` — promoting
  what used to be a lazy first-deploy install into an explicit
  admin-triggered step) and its build/prepare step
  (`build(RuntimeBuildContext)`). Adding a new runtime means adding one new
  plugin + one catalog entry — no existing plugin or orchestration code
  changes.
- **Independent lifecycle.** Installing, updating, or removing an
  Application never touches a running App's deploy/restart/rollback flow;
  conversely, `App.runtime` stays in sync with `application.key` so existing
  tooling that reads the denormalized `runtime` column keeps working
  unchanged.

## Network exposure modes

Not every `App` is an HTTP service behind Nginx — a game server, an MQTT
broker, a gRPC service, or any other TCP-speaking custom protocol needs the
same systemd sandboxing and resource limits as a web app, but no reverse
proxy or domain. `App.exposeMode` (set at creation, immutable afterward)
picks one of three tiers:

| Mode | Nginx / domain? | Reachability | Firewall |
|---|---|---|---|
| `web` (default) | Yes — vhost + optional Domain/TLS | via the assigned domain (or the host IP on port 80/443) | opened once, for Nginx |
| `tcp` | None | app binds `0.0.0.0:<internalPort>` itself | `ufw allow <port>/tcp` opened/closed on demand via `publiclyReachable` |
| `internal` | None | `127.0.0.1` only — other local processes | never opened |

`tcp` apps skip the `apply-vhost` step of the deployment pipeline entirely
and instead have the worker call the agent's `expose-port`/`unexpose-port`
subcommands (thin wrappers around the same `ufw allow`/`ufw delete allow`
helpers used by `PostgresService`/`MongoService` public exposure) to open or
close the host firewall for their port. Toggling `publiclyReachable` on an
existing `tcp` app (`POST /apps/{id}/network`) reconciles the firewall via a
dedicated `gisila:queue:network` job — no rebuild, no restart. Domains are
rejected outright for `tcp`/`internal` apps (`DomainsService.add`) since
there's no vhost for a hostname to attach to.

## Multi-tenancy & isolation

| Boundary | Mechanism |
|---|---|
| Process | one systemd unit per app, dedicated Linux user |
| FS | `ProtectSystem=strict`, `ProtectHome`, `ReadWritePaths` restricted to `/srv/apps/<user>/` |
| Memory | systemd `MemoryMax=…M` (cgroups v2) |
| CPU | `CPUQuota=…%` |
| Processes | `TasksMax=…` |
| Privileges | `NoNewPrivileges`, `RestrictNamespaces`, `MemoryDenyWriteExecute`, `LockPersonality` |
| Network | `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6`; `web`/`internal` apps are proxied from/reachable only via `127.0.0.1:port`, `tcp` apps bind `0.0.0.0:port` directly with the host firewall gating public reachability (see [Network exposure modes](#network-exposure-modes)) |
| Syscalls | `SystemCallArchitectures=native`; AppArmor + seccomp profile |
| Mandatory access | per-app AppArmor profile generated by the agent |

The panel itself runs as the unprivileged `gisila` user. The only way it
can touch the host is through `sudo /usr/local/bin/gisila-agent …`, gated
by `/etc/sudoers.d/gisila`.

## Why no Docker?

The MVP optimises for **density on cheap VPSs**. Each Docker container
adds ~20-100 MB of resident overhead (`containerd-shim`, image FS,
networking namespaces) before your app's runtime is even running. A bare
systemd unit adds approximately zero. On a 1 GB VPS the difference
between 8 containers and 30 sandboxed processes is dramatic.

Optional Docker isolation is on the roadmap as an alternative deployment
engine for tenants that explicitly want it.

## Future scalability

The control plane is stateless (aside from Postgres + Redis), so:

- **Multiple nodes** — add a `Node` model and route deployments to the
  closest agent. The worker is the only piece that needs to grow a node
  selector.
- **Cluster scheduling** — bin-pack deployments across nodes by memory
  pressure (`cgroups` reports). Same shape, different policy.
- **Optional Docker isolation** — a second agent implementation that
  takes the same CLI surface but provisions containers instead of
  systemd units.
- **Horizontal scaling of an app** — multiple `App` rows pointing at
  the same project, each with its own port; nginx upstreams round-robin.
- **Managed databases / object storage** — separate gisila-managed
  services that show up as siblings of `App` and have their own
  resource model.
