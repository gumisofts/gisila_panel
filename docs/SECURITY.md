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
6. **Network** — `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6`. A
   `web` app (the default) only ever listens on `127.0.0.1:<port>`; Nginx
   is its sole public ingress. A `tcp`/`internal` app (see
   [Network exposure modes](DEPLOYMENT_ENGINE.md#network-exposure-modes))
   binds `0.0.0.0:<port>` itself, with public reachability gated by a host
   firewall (`ufw`) rule the panel opens/closes explicitly — never by
   default. Firewall changes never touch `ufw`'s default policy, and
   [`Priv.ufwDeny`](../agent/lib/runtime/priv.dart) refuses to remove a rule
   for any port that matches the host's configured SSH port (always `22`,
   plus whatever `Port` directive `sshd_config`/`sshd_config.d` declares) —
   so no combination of app config or worker bug can firewall the operator
   out of the box over SSH.
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
11. **Panel secrets stay out of tenant processes** — the panel and worker
    run the agent with an allowlisted environment, and the agent starts builds
    and Console commands from a minimal one, so nothing from
    `/etc/gisila/.env` (JWT secret, database passwords) reaches an app user's
    shell. When root runs `runuser` for a build, it does so by absolute path
    and without the loader variables glibc strips for setuid programs
    (`LD_PRELOAD`, `GLIBC_TUNABLES`, …). The shared pnpm install never sees
    the app's env vars.
12. **Generated config files** — every agent option that is rendered into a
    systemd unit, supervisor conf or env file rejects control characters, so
    a newline can't add directives (`ExecStartPre=+…` runs as root). Env var
    names must be plain identifiers.

## Authorization

- Node-global infrastructure — services, Postgres/Mongo instances and
  databases, object storage, mail — is superuser-only, in the API and in the
  UI. Linking a storage bucket to an app is too, since it puts the bucket's
  keys in an env any developer can read.
- App resources need a role in the app's team; the log WebSockets apply the
  same rule as the REST routes (and a build-log socket's deployment must
  belong to that app).
- An app can only be pointed at an SSH deploy key its actor owns.
- Backups are served only under the database and instance they belong to.

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
