---
title: "Why We Skipped Docker for Our PaaS"
description: "Container overhead is real. On a 1 GB VPS, native Linux processes beat Docker for density — without sacrificing isolation."
date: 2026-06-10
author: Gisila Team
tags: [architecture, docker, systemd, performance, self-hosting]
---

# Why We Skipped Docker for Our PaaS

When we started building Gisila Panel, the first question people asked was predictable:

> *"Why not just use Docker?"*

It's a fair question. Docker is the default answer for "how do I run apps on a server?" in 2026. Coolify wraps Docker. CapRover wraps Docker. Dokku wraps Docker. Even Railway and Render ultimately run containers under the hood.

We chose a different path: **every app on Gisila Panel is a native Linux process managed by systemd**, isolated with Linux users, AppArmor, cgroups v2, and seccomp.

This post explains why.

---

## The RAM tax nobody talks about

When you run an app in Docker, you're not just running your app. You're also running:

- A container runtime shim (`containerd-shim` or equivalent)
- An isolated network namespace
- An isolated mount namespace
- Image filesystem layers (even when shared, there's bookkeeping overhead)
- The container's own init process

**Each container adds roughly 20–100 MB of resident memory overhead** before your application's runtime is even loaded.

For a Go binary that uses 8 MB at idle, that overhead is 3–12× the app itself. For a Rust service at 15 MB, you're paying 2–7× just to exist.

Now multiply that across ten apps on a 1 GB VPS:

| Approach | Overhead per app | 10 apps | Apps that fit on 1 GB |
|----------|-----------------|---------|----------------------|
| Docker container | ~20–100 MB | 200 MB–1 GB wasted | ~8–15 |
| systemd unit | ~0 MB | ~0 MB wasted | ~30–100+ |

On a 1 GB VPS, the difference between 8 containerized apps and 30 sandboxed native processes is not marginal. It's the difference between "this VPS is full" and "I have room for another dozen services."

A bare systemd unit adds approximately zero overhead. Your Go binary is your Go binary. Nothing else is resident.

---

## What "native" actually means

When Gisila Panel deploys your app, here's what happens on the host:

1. A dedicated Linux user is created (`app_<random>`)
2. Your code is cloned or extracted to `/srv/apps/app_xxx/`
3. The runtime builds your app (`go build`, `cargo build`, `dart compile exe`, etc.)
4. A systemd unit file is generated with hardening directives
5. An AppArmor profile is generated and loaded
6. An Nginx vhost is written pointing to `127.0.0.1:<port>`
7. `systemctl start gisila-app_xxx` — your binary runs

There is no image pull. No layer extraction. No container start. Your compiled binary is `exec`'d directly by systemd.

The filesystem layout follows a Capistrano-style release structure:

```
/srv/apps/app_xxx/
├── current/      → symlink to active release
├── releases/     → timestamped deployment artifacts
├── shared/       → persistent data (env, uploads)
├── tmp/          → scratch space
└── logs/         → app-specific logs
```

Rollbacks swap the `current/` symlink and restart the unit. No rebuild required if the artifact is cached.

---

## "But what about isolation?"

This is the second most common question, and it's the right one. Containers exist partly because running arbitrary code on a shared host is dangerous. If we skip Docker, how do we keep tenants apart?

We use the same kernel primitives Docker uses — just without the container wrapper.

### Layer 1: Identity isolation

Each app gets its own Linux user:

- System account (`--system`), no login shell (`/usr/sbin/nologin`)
- No home directory
- Cannot escalate through PAM modules that filter `uid >= 1000`

App A cannot read App B's files because the filesystem permissions say so — the same guarantee Docker provides via user namespaces, but enforced by the kernel directly.

### Layer 2: Filesystem isolation

Every systemd unit declares:

```
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/srv/apps/<user>/shared /srv/apps/<user>/tmp /srv/apps/<user>/logs
ReadOnlyPaths=/srv/apps/<user>/current /srv/apps/<user>/releases
PrivateTmp=true
```

An app can only write to its own directories. Everything else on the filesystem is read-only or invisible.

### Layer 3: AppArmor mandatory access control

The `gisila-agent` generates a per-app AppArmor profile on every deployment. The profile default-denies access outside the app's work directory and common runtime support files (`/usr/lib`, `/tmp`, etc.).

Profiles are loaded with `apparmor_parser -r` and enforced by the kernel — the same mechanism LXD and Docker use internally.

### Layer 4: Kernel hardening via systemd

Every unit sets:

- `NoNewPrivileges=true` — no setuid escalation
- `RestrictNamespaces=true` — no new mount/PID/network namespaces
- `MemoryDenyWriteExecute=true` — W^X enforcement
- `LockPersonality=true` — no personality changes
- `RestrictRealtime=true` — no realtime scheduling abuse
- `ProtectKernelTunables=true` — no `/proc/sys` writes
- `PrivateDevices=true` — no direct hardware access
- `SystemCallArchitectures=native` — 64-bit syscalls only

### Layer 5: Resource limits via cgroups v2

- `MemoryMax=<limit>M` — hard memory cap; OOM-kill is local to the cgroup
- `CPUQuota=<percent>%` — CPU throttling
- `TasksMax=<n>` — process count limit
- `LimitNOFILE=<n>` — file descriptor limit

One runaway tenant cannot starve the host. OOM kills only that app's processes.

### Layer 6: Network isolation

- `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6`
- Apps listen only on `127.0.0.1:<assigned-port>` — never on the public interface
- Nginx is the sole public ingress; TLS termination happens at the edge

### The isolation comparison

| Boundary | Docker | Gisila Panel (systemd) |
|----------|--------|------------------------|
| Process | container namespace | dedicated Linux user + systemd unit |
| Filesystem | mount namespace + overlay FS | `ProtectSystem=strict` + AppArmor |
| Memory | cgroup v2 | cgroup v2 (`MemoryMax`) |
| CPU | cgroup v2 | cgroup v2 (`CPUQuota`) |
| Network | bridge/overlay network | localhost only + Nginx proxy |
| Syscalls | seccomp profile | AppArmor + systemd seccomp |
| Privileges | dropped capabilities | `NoNewPrivileges` + no setuid |

The mechanisms are the same. The wrapper is different.

---

## When Docker *is* the right choice

We're not anti-Docker. Docker is excellent for:

- **Reproducible dev environments** — "works on my machine" solved
- **Polyglot dependency hell** — when your app needs exotic system libraries
- **OCI image distribution** — shipping the same artifact to multiple environments
- **Orchestration at scale** — Kubernetes, Swarm, Nomad

Optional Docker isolation is on our roadmap (v0.5) as an **alternative deployment engine** for tenants that explicitly want it. The API and agent interface stay the same; only the backend changes.

But for the MVP — and for our target user — Docker is the wrong default.

Our target user has:

- A $5–20/month VPS
- 10–50 small compiled backend services
- Go, Rust, Dart, or Python apps with minimal system dependencies
- A desire for Heroku-style DX without the RAM tax

For that user, native Linux execution is strictly better on every axis that matters: density, startup time, memory footprint, and operational simplicity.

---

## The operational simplicity argument

There's a less quantifiable benefit: **fewer moving parts**.

A Docker-based panel on a VPS needs:

- Docker Engine (or containerd + nerdctl)
- A container registry or local image store
- Docker networking (bridge, overlay, or host mode)
- Volume management for persistent data
- Image garbage collection
- Container health monitoring

A Gisila Panel node needs:

- systemd (already there)
- Nginx (already there)
- AppArmor (already there)
- PostgreSQL + Redis (for the control plane)

When something breaks at 2 AM, `journalctl -fu gisila-app_myapi` tells you exactly what happened. There's no "is it the container or the app?" ambiguity. The process *is* the app.

---

## The density math, concretely

Let's walk through a realistic scenario.

**Setup:** Hetzner CX22 — 2 vCPU, 4 GB RAM, ~€4/month.

**Apps:** 25 small backend services (Go APIs, Rust workers, Dart web servers). Average idle RAM: 12 MB each. Average peak RAM: 80 MB each.

### With Docker (Coolify-style)

| Resource | Usage |
|----------|-------|
| Container overhead (25 × 40 MB avg) | 1,000 MB |
| App runtime (25 × 12 MB idle) | 300 MB |
| Control plane (panel + DB + Redis) | 400 MB |
| OS + buffer | 300 MB |
| **Total idle** | **~2,000 MB** |
| **Headroom for peaks** | ~2 GB (tight) |

You'd feel memory pressure with normal traffic spikes. You might fit 25 apps, but you'd be watching `free -h` regularly.

### With Gisila Panel (native systemd)

| Resource | Usage |
|----------|-------|
| Container overhead | 0 MB |
| App runtime (25 × 12 MB idle) | 300 MB |
| Control plane (panel + DB + Redis) | 400 MB |
| OS + buffer | 300 MB |
| **Total idle** | **~1,000 MB** |
| **Headroom for peaks** | ~3 GB (comfortable) |

Same 25 apps. Half the idle RAM. Room to grow to 50+ before you'd need a bigger box.

---

## Conclusion

We didn't skip Docker because containers are bad. We skipped Docker because **for our use case — high-density compiled backend hosting on cheap VPSs — the container wrapper costs more than it delivers**.

systemd + AppArmor + cgroups v2 gives you the same isolation guarantees with zero per-app RAM overhead. Nginx gives you the same edge routing. Let's Encrypt gives you the same TLS.

What you get back is density, simplicity, and a hosting bill that stays at $5/month even as your app count grows.

That's the bet Gisila Panel is making. So far, it's working.

---

**Next:** [How a Deployment Works →](./03-how-a-deployment-works.md)
