---
title: "Introducing Gisila Panel"
description: "An open-source, lightweight PaaS for compiled backends, like Heroku, but native."
date: 2026-06-10
author: Gisila Team
tags: [introduction, paas, self-hosting, open-source]
---

# Introducing Gisila Panel

**Deploy compiled backends like it's 2010, without the pain of 2010.**

If you've ever shipped a Go API, a Dart server, or a Rust microservice, you know the drill: push to git, wait for a build, get a URL back, tail logs in a browser, attach a domain, and move on. Heroku made that workflow feel effortless. Railway, Render, and Fly.io carried it forward.

Then the bill arrives.

A handful of small side projects on a managed PaaS can easily cost $40–100/month. For hobby apps, internal tools, and client microservices, that adds up fast. The obvious alternative is self-hosting, but most self-hosted panels assume you want Docker or Kubernetes, and that assumption comes with a cost of its own.

**Gisila Panel** is our answer: an open-source, self-hostable hosting panel that gives you the Heroku developer experience without the container overhead.

---

## The problem we're solving

Modern PaaS platforms fall into two camps, and neither is ideal for everyone.

### Managed PaaS is expensive at scale

Heroku, Railway, and Render are genuinely great products. Push code, get a URL, done. But pricing is per-app and per-resource. Run ten small APIs and you're paying for ten dynos, even when each one idles at 5 MB of RAM most of the day.

For indie developers, agencies running client microservices, and teams with dozens of internal tools, the math stops working.

### Self-hosted panels assume containers

Coolify, CapRover, Dokku, and similar tools are powerful, but they wrap every app in a container. Each container carries **20–100 MB of resident overhead** before your runtime even starts: `containerd-shim`, image filesystem layers, networking namespaces, and more.

On a 1 GB VPS, that overhead matters. You might fit 8 containerized apps comfortably. You could fit 30+ sandboxed native processes in the same box.

### The gap in the middle

What if you want:

- **Heroku-style DX**: git push to deploy, live logs, env vars, custom domains, automatic TLS
- **Self-hosted control**: your server, your data, your pricing
- **High density**: many apps on a cheap VPS without wasting RAM on container daemons
- **Real isolation**: multi-tenant hosting where one bad app can't take down the rest

That's the gap Gisila Panel fills.

---

## What Gisila Panel is

Gisila Panel is a **lightweight PaaS hosting panel** optimized for compiled backend applications:

- **Dart**
- **Go**
- **Rust**
- **Zig**
- **Bun**
- **Node.js**
- **Python**

Plus **static sites**, **pre-built binaries**, and **Celery** workers.

It works like Heroku, Railway, or Render, but instead of Docker or Kubernetes, it runs each app as a **native Linux process under systemd**, with per-app isolation via Linux users, AppArmor, cgroups v2, seccomp, and Nginx reverse proxying.

Three words sum up the approach: **open-source · self-hostable · zero-container**.

---

## Core philosophy

Every design decision follows from a small set of principles:

| Principle                   | What it means                                             |
| --------------------------- | --------------------------------------------------------- |
| **High-density hosting**    | Pack many apps onto a small VPS                           |
| **Low RAM usage**           | No per-app container daemon                               |
| **Low-cost VPS friendly**   | Comfortable on a 1 GB / 1 vCPU box                        |
| **Minimal overhead**        | Straight `exec` of native binaries via systemd            |
| **Secure multi-tenant**     | Every app gets its own Linux user and sandbox             |
| **Compiled backends first** | Optimized for Go, Rust, Dart, and friends, not WordPress |
| **Open-source first**       | MIT licensed, self-hostable, modern UI                    |

The target user isn't running a Kubernetes cluster. They're running a **$5–20/month VPS** and want to host 20–100 small services on it without babysitting systemd units by hand.

---

## What you get today

### Deploy and run apps

- Create apps with multiple runtimes: `dart`, `go`, `rust`, `zig`, `bun`, `node`, `python`, `binary`, `celery`, `static`
- A **runtime catalog**: install, pin, and remove toolchain versions independently of the panel itself (Python 3.11 next to 3.13, Node 20 next to 24)
- Deploy from a git repository, a binary upload, or a ZIP archive
- Full deployment pipeline: provision → build → apply systemd unit → apply Nginx vhost → restart
- Start, stop, and restart apps from the dashboard
- Roll back to previous deployment artifacts
- Environment variables, including secrets
- Custom domains with automatic Let's Encrypt TLS
- Live build logs streamed to the browser via WebSocket
- Per-app CPU and RAM metrics sampled from cgroups
- App console for one-off commands
- Resource limits: memory, CPU quota, task limits

### Teams and access control

- JWT authentication and personal API tokens (`gsl_…`)
- Teams, projects, and role-based access (`owner`, `admin`, `developer`, `viewer`)
- SSH keys and deploy keys
- Audit logs and app event history

### Infrastructure beyond apps

- **Databases**: PostgreSQL and MongoDB instances from the dashboard
- **Managed services**: Redis, Memcached, SMTP, Mailpit, and similar sidecars
- **Object storage**: buckets for app uploads and artifacts
- **Mail hosting**: Postfix + Dovecot virtual mailboxes with DKIM/DMARC DNS

### Admin and API

- Gisila Studio admin panel at `/admin`
- Full REST API with Swagger docs at `/docs`
- WebSocket endpoints for live logs and events

---

## How it works (at a glance)

```
┌──────────────┐   HTTPS   ┌──────────────────┐
│  React UI    │ ────────▶ │  Dart API server │
│  (Vite)      │           │  (gisila stack)  │
└──────────────┘           └─┬─────────────┬──┘
                             │             │
                             ▼             ▼
                       ┌──────────┐  ┌──────────┐
                       │ Postgres │  │  Redis   │
                       └──────────┘  └─────┬────┘
                                           │ jobs
                                           ▼
                               ┌───────────────────┐
                               │  gisila-worker    │
                               └────────┬──────────┘
                                        │
                                        ▼
                               ┌───────────────────┐
                               │  gisila-agent     │ (root, host-side)
                               └────────┬──────────┘
                                        │
                    ┌────────┬────────┼────────┬────────┐
                    │ app1   │ app2   │ app3   │ appN   │
                    │systemd │systemd │systemd │systemd │
                    └────────┴────────┴────────┴────────┘
```

When you trigger a deployment, the API queues a job in Redis. The worker picks it up and calls `gisila-agent`, a privileged host-side binary that provisions a Linux user, builds your app, writes a systemd unit and AppArmor profile, configures Nginx, and starts the service. Build output streams back to the UI in real time.

Each hosted app is a plain systemd service running as its own unprivileged Linux user. Nginx terminates TLS and proxies to `127.0.0.1:<assigned-port>`. No container runtime involved.

The control plane, worker, and agent are Dart, compiled to native binaries. The dashboard is React 19 with IBM Carbon. PostgreSQL stores state; Redis handles queues and pub/sub for live log streaming.

---

## Who is this for?

**Gisila Panel is a good fit if you:**

- Run multiple small backend services (APIs, workers, webhooks, cron-adjacent jobs)
- Want Heroku-style workflows without Heroku pricing
- Have a cheap VPS and want to maximize how many apps it holds
- Prefer compiled languages (Go, Rust, Dart, Zig) over PHP/WordPress-style hosting
- Need multi-tenant isolation on a single node
- Value open-source and self-hosting

**Gisila Panel is probably not for you if you:**

- Need Kubernetes-style orchestration across a fleet of nodes (multi-node is on the roadmap, but not the current focus)
- Primarily host WordPress or PHP monoliths
- Require Docker/OCI images as your deployment unit (optional Docker isolation is planned, but not shipped yet)
- Need managed infrastructure at hyperscaler scale

---

## The numbers

We designed Gisila Panel around a simple cost comparison:

| Approach                       | Typical monthly cost        | Apps on a 1 GB VPS  |
| ------------------------------ | --------------------------- | ------------------- |
| Managed PaaS (Heroku/Railway)  | $40–100+ for ~10 small apps | N/A (cloud-managed) |
| Docker-based self-hosted panel | $5–20 VPS + your time       | ~8–15 apps          |
| **Gisila Panel**               | **$5–20 VPS + your time**   | **30–100+ apps**    |

> _We replaced a $40/mo Heroku bill with a $5 VPS running gisila. 28 apps, one box, zero containers, identical DX._

That's the pitch in one sentence.

---

## Built on the gisila stack

Gisila Panel isn't a standalone project: it's part of the **gisila stack**, an open-source toolkit for building Dart web applications:

- **`gisila`**: Shelf-based MVC framework
- **`gisila_orm`**: schema-driven ORM with migrations
- **`gisila_doc`**: OpenAPI/Swagger generation
- **`gisila_studio`**: admin panel framework
- **`gisila_jobs`**: Redis-backed task queue (a Celery replacement)

We eat our own cooking: Gisila Panel is deployed and managed the same way it deploys your apps.

---

## Getting started

Gisila Panel is MIT licensed and available now. The fastest path is a **prebuilt install** on Ubuntu 22.04+ or Debian 12+. No Dart SDK, no Node, nothing compiled on the box:

```bash
curl -fsSL https://raw.githubusercontent.com/gumisofts/gisila_panel/main/infra/install-prebuilt.sh \
  | sudo env PANEL_DOMAIN=panel.example.com ISSUE_TLS=1 bash
```

You need a reachable PostgreSQL 16+ database and Redis instance (same host or remote). Register an account in the dashboard, create an app, click Deploy.

The full walkthrough (Postgres setup, first app, domains, tokens, updates, uninstall) is in **[Install and Getting Started](./04-install-and-getting-started.md)**.

To poke at the UI locally without a VPS:

```bash
git clone https://github.com/gumisofts/gisila_panel.git
cd gisila_panel
docker compose up
```

Open [http://localhost:3000](http://localhost:3000). In Docker, the worker logs the agent commands it *would* run and does not touch systemd.

---

## What's next

We're actively building toward:

- **v0.2**: GitHub webhook auto-deploy, Argon2id, 2FA, health checks, runtime log streaming
- **v0.3**: Multi-node scheduling across a fleet of VPSs
- **v0.4**: One-click templates ("Deploy Ghost", "Deploy Strapi"), managed Postgres/Redis as first-class objects
- **v0.5**: Optional Docker isolation for tenants that explicitly want containers

Follow along, star the [repo](https://github.com/gumisofts/gisila_panel), and try it on a spare VPS. We'd love to hear what you deploy.

---

**gisila panel · MIT · built with the gisila stack**

**Next:** [Why We Skipped Docker →](./02-why-we-skipped-docker.md)
