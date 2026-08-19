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

### Postgres and Redis are dependencies, not components

Neither is installed or managed by the panel — it is a client of both. They can
be on the panel host, on another machine on the network, or on a managed
provider; `database.yaml` and `REDIS_HOST`/`REDIS_PORT` in `/etc/gisila/.env`
are the only things that decide. The systemd units order themselves *behind* a
local `postgresql.service` / `redis-server.service` if one is installed, but
must never `Requires=` them: on a host where those units don't exist, that
would refuse to start the panel at all.

The Databases page complicates this slightly, because it registers the panel's
own cluster as a read-only **system instance** so operators can see it
alongside the ones they install. Every instance the panel *installs* is created
by the agent on this host, so it is always on loopback with a systemd unit, a
data directory and a local socket to drive. The system instance is the sole
exception, and the split is explicit in the code:

| Helper (`services/postgres_service.dart`) | Meaning |
|---|---|
| `isSystemInstance(i)` | The cluster behind `database.yaml` (matched by port). |
| `instanceHost(i)` | `127.0.0.1`, or `database.yaml`'s host for the system one. |
| `isLocalInstance(i)` | Whether the agent can act on it at all. |
| `statsTarget(i)` | `gisila_monitor` locally; the panel's own credentials remotely. |

When `isLocalInstance` is false the API refuses every agent-backed operation
with a 422 that says where the cluster actually lives, the worker drops any
such job already in the queue, the metrics sampler skips it (no systemd unit
here to stat), and the UI hides the controls rather than offering buttons that
can only fail. Reads still work: metrics and settings come over a direct
connection using the panel's own credentials, since the `gisila_monitor` role
the agent provisions locally can't exist on a host it cannot reach.

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

Because a `tcp` app's start command can't be guessed the way a web app's can,
it's required for some runtimes — see
[A `tcp` app has to say what to run](DEPLOYMENT_ENGINE.md#a-tcp-app-has-to-say-what-to-run).

## Health monitoring & repair

`HealthMonitorWorker` probes the mail stack, every installed `ManagedService`
and every installed runtime toolchain on a timer, caching each result in Redis
under `gisila:healthstat:*`. That snapshot is what `GET /mail/health`,
`GET /services/{id}/health` and the alert evaluator all read — the lifecycle
`status` column only says "did the last install job succeed", not "is it up
right now".

Mail and services are auto-repaired (restart, escalating to reinstall) on a
cooldown when a probe finds them unhealthy, and a superuser can trigger the
same repair sooner from the UI.

**Repairs report their outcome.** A repair runs on the worker, so the HTTP
call only queues it — and the agent exits 0 whether or not the stack came
back, reporting post-repair health in its JSON payload instead. The worker is
therefore responsible for reading that payload and writing the verdict into
the health snapshot the moment the job ends, rather than leaving the UI to
infer it from the next periodic probe:

| Field | Meaning |
|---|---|
| `detail` | Human-readable summary of what is currently down (`"postfix is not running; nothing is listening on imaps (port 993)"`) |
| `lastRepairAt` | When the last repair finished (also drives the auto-repair cooldown) |
| `lastRepairStatus` | `running` \| `succeeded` \| `failed` |
| `lastRepairDetail` | Why it failed, when it did |
| `lastRepairSteps` | Ordered log of what the repair attempted, including the steps that errored |

Periodic probes deliberately carry the `lastRepair*` fields forward: a probe
reports health, it is not a repair, so overwriting them would erase the
outcome on the very next tick. The UI polls the snapshot after queueing a
repair and reports success or the actual failure reason once `lastRepairAt`
advances.

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
