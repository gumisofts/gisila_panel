# Roadmap

## v0.1 · MVP (current scope)

- [x] Dart backend on the gisila stack (control plane + worker).
- [x] Postgres schema for users · teams · projects · apps · deployments
      · env vars · domains · metrics · audit logs.
- [x] JWT + personal API token auth.
- [x] Privileged `gisila-agent` with systemd / nginx / AppArmor /
      certbot generators.
- [x] Redis-backed job queue (deployments · lifecycle · vhosts · ssl).
- [x] Next.js dashboard: dashboard · apps · app detail (overview /
      deployments / env / domains / live logs / metrics).
- [x] systemd units + nginx vhost + sudoers rule for the panel itself.
- [x] `infra/install.sh` single-node installer.
- [x] **Application registry** — runtimes decoupled from the panel into an
      independently install/update/removable `Application` catalog
      (`RuntimePlugin` + `RuntimeRegistry` on the agent, `ApplicationService`
      + `/applications` API on the backend), with per-application
      deployment modes (`build_execute` / `direct_run` / `static_publish`).

## v0.2 · Production hardening

- [ ] **Argon2id** password hashing (replace salted SHA-256).
- [ ] **Refresh tokens** + token revocation list.
- [ ] **2FA** (TOTP first, WebAuthn later).
- [ ] **GitHub integration** — webhook receiver auto-triggers
      deployments on push.
- [ ] **Build artifact storage** — store compiled binaries under
      `/srv/gisila/artifacts/<hash>` so rollbacks don't re-build.
- [ ] **Metrics collector** — small Dart sidecar that scrapes
      `/sys/fs/cgroup/.../memory.current` and
      `cpu.stat` for each app every 10 s.
- [ ] **Real-time runtime log streaming** — `journalctl -fu` per app,
      published on `gisila:logs:runtime:<appId>`.
- [ ] **Health checks** with auto-restart on failure (`health_check_path`
      probed by the agent).
- [ ] **Disk quotas** (XFS quotas or `quota` package).

## v0.3 · Multi-node

- [ ] `Node` model + heartbeat from agents.
- [ ] Worker becomes a scheduler that picks the least-loaded node.
- [ ] Agent gains an SSH backend (instead of local sudo).
- [ ] App `replicas` setting → multiple systemd units across nodes,
      nginx upstreams round-robin.

## v0.4 · Marketplace & managed services

- [ ] Managed Postgres / Redis: stand up the service in its own systemd
      unit, hand connection details to apps via auto-injected env vars.
- [ ] One-click templates ("Deploy Ghost", "Deploy Strapi", …).
- [ ] Object storage adapter (MinIO sidecar).
- [ ] Background workers as first-class objects (`WorkerApp`, sharing
      the same artifact as the web app, different start command).

## v0.5 · Optional Docker isolation

- [ ] Alternate agent backend that builds OCI images and runs them with
      `crun` or `runc`, retaining the same CLI surface.
- [ ] Cgroup memory pressure → preemptive scaling triggers.

## v1.0 · Enterprise extensibility

- [x] Plugin system for builtin runtimes (see v0.1 **Application registry**);
      remaining scope: dynamic/remote plugin loading for *custom*,
      non-builtin build steps + auth providers + runtimes.
- [ ] SAML / OIDC SSO.
- [ ] Audit log export (S3 / SIEM).
- [ ] Multi-tenancy with org-level isolation (Postgres schemas).
- [ ] Billing — per-team usage metering hooked into Stripe.

## Long-term ideas

- Built-in HTTP edge cache (Varnish / cache-friendly nginx tier).
- Cron jobs (`systemd-timer` generator).
- Preview environments per PR.
- Internal `gisila login` CLI that turns a Linux box into a registered
  deploy target via the same tokens.
