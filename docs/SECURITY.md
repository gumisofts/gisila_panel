# Security model

## Threat model

We optimise for the **single-VPS, multi-tenant** case: a hostile tenant
must not be able to read, modify, or interfere with any other tenant's
files, processes, network traffic, or systemd state, and must not be
able to reach the panel's database / Redis directly.

## Layered defences

1. **Identity isolation** — each app gets its own Linux user
   (`app_<6 chars>`). The user has no login shell (`/usr/sbin/nologin`),
   no home, and is created with `--system` so it cannot accumulate
   privileges through PAM modules that filter `>= 1000`.
2. **Filesystem isolation** — `/srv/apps/<user>/` is owned `0750` by the
   app's user. The systemd unit declares
   `ReadWritePaths=<work_dir>/shared <work_dir>/tmp <work_dir>/logs` and
   `ReadOnlyPaths=<work_dir>/current <work_dir>/releases`, on top of
   `ProtectSystem=strict` and `ProtectHome=true`.
3. **AppArmor mandatory access** — the agent generates a profile per
   app that default-denies everything outside the work dir + common
   runtime support files. Profiles are loaded with `apparmor_parser -r`
   on each deployment.
4. **Kernel surface** — `RestrictNamespaces`, `LockPersonality`,
   `MemoryDenyWriteExecute`, `RestrictRealtime`, `ProtectKernel*`,
   `PrivateDevices` and `SystemCallArchitectures=native` are all set on
   every unit.
5. **Resources** — cgroups v2 `MemoryMax`, `CPUQuota`, `TasksMax`,
   `LimitNOFILE`. OOM-kill is local to the cgroup; one runaway tenant
   cannot starve the host.
6. **Network** — `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6`.
   Nginx is the only public ingress; apps only listen on
   `127.0.0.1:<assigned-port>` and never on the public interface.
7. **TLS** — Let's Encrypt via `certbot --nginx`. Certs are renewed by
   the standard cron, not by the panel.
8. **Privilege separation** — the API and worker run as the unprivileged
   `gisila` user. The only privileged code path is invoking
   `gisila-agent` through a tightly scoped sudoers rule
   ([`infra/sudoers.d_gisila`](../infra/sudoers.d_gisila)).
9. **Input validation** — the agent rejects any `--user`, `--work-dir`,
   `--hostname`, `--runtime`, or `--source-type` that doesn't match a
   strict regex before invoking `useradd`, `systemctl`, `certbot`, etc.
   `--build-command` and `--start-command` are passed verbatim but must
   not contain shell-metacharacters (`|`, `&`, `;`, ` `` `, `$`, `<`,
   `>`).
10. **Secrets** — passwords are salted SHA-256 (Argon2 upgrade on the
    roadmap). API tokens are stored as SHA-256 hex + a 12-char prefix
    used as a lookup index. JWTs are signed with `JWT_SECRET` (HMAC).

## Authentication

| Bearer | Where |
|---|---|
| JWT (`HS256`, 14d default) | UI sessions, default for `/auth/login`. |
| Personal API token (`gsl_…`) | CLI / CI. Issued once, hashed at rest, revocable. |

The panel uses **same-origin cookies free** auth: tokens live in
`localStorage` and are sent as `Authorization: Bearer`. CORS is
permissive by default (override in `AppConfig.cors`).

## Audit & traceability

- `app_events` records every state-changing user action on an app
  (`deploy`, `restart`, `stop`, `env_set`, `domain_add`, `rollback`).
- `audit_logs` records cross-cutting events (`team.invite`,
  `token.issue`, …).
- `gisila-agent` always writes a JSON status line on success / failure
  so the worker can correlate output with deployments.

## What we still need to harden (roadmap)

- Argon2id password hashing (depends on a pure-Dart implementation we
  trust).
- Refresh tokens + revocation list.
- TOTP / WebAuthn 2FA.
- Outbound network policy per app (right now apps share the host's
  egress namespace; future work: per-app netfilter rules).
- Optional Linux user namespaces / Firejail-style sandboxes.
- Disk quotas (`quota`, `xfs_quota`) — currently the only limit is
  `TasksMax` and process memory.
