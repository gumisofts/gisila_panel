# API reference

The API is described by a live OpenAPI 3.1 spec served at
`/openapi.json`, with Swagger UI at `/docs` and ReDoc at `/redoc`. What
follows is a high-level map.

All endpoints accept either:

- `Authorization: Bearer <jwt>` — a session token from `POST /auth/login`
  (or `POST /auth/login/mfa` for an account with two-factor auth), or
- `Authorization: Bearer gsl_<…>` — a personal API token from
  `POST /me/security/tokens`, or
- `X-API-Token: gsl_<…>` — same as above, useful for CLI clients.

Accounts are created by a superuser (`POST /auth/users`); there is no public
sign-up.

## Auth

| Method | Path | Body | Notes |
|---|---|---|---|
| `POST` | `/auth/login` | `{email, password}` | Public. Returns `{user, access}`, or `{mfaRequired: true, challenge}` when the account has 2FA on. |
| `POST` | `/auth/login/mfa` | `{challenge, code}` | Public. `code` is a TOTP code or a recovery code. Returns `{user, access}`. The challenge is valid for 5 minutes. |
| `GET`  | `/auth/me` | — | Auth required. |
| `POST` | `/auth/change-password` | `{oldPassword, newPassword}` | Signs out every other session; returns a new `access` token for this one. |
| `POST` | `/auth/sessions/revoke` | — | Signs out every other session; returns a new `access` token. API tokens are not affected. |
| `GET`  | `/auth/totp` | — | `{enabled, recoveryCodesRemaining}`. |
| `POST` | `/auth/totp/setup` | `{password}` | Starts setup. Returns `{secret, otpauthUri}`. |
| `POST` | `/auth/totp/enable` | `{code}` | Confirms setup. Returns `{recoveryCodes, access}` and signs out other sessions. |
| `POST` | `/auth/totp/disable` | `{password, code}` | `code` may be a recovery code. |
| `POST` | `/auth/totp/recovery-codes` | `{code}` | Replaces the recovery codes. Needs an authenticator code. |
| `DELETE` | `/auth/users/{id}/totp` | — | Superuser only. Turns a user's 2FA off and signs them out. |

Failed sign-ins are throttled in Redis: 10 per account per address, 50 per
account and 100 per address in a 15-minute window, after which the endpoint
answers `429` until the window ends. A second-factor code is throttled the same
way.

## Teams & projects

| Method | Path | Notes |
|---|---|---|
| `GET`/`POST` | `/teams/` | List my teams · create one. |
| `GET` | `/teams/{id}` | Team detail. |
| `GET` | `/teams/{id}/members` | List members. |
| `POST` | `/teams/{id}/invitations` | Invite by email. |
| `GET`/`POST` | `/projects/?teamId=` | List + create. |
| `GET`/`PATCH`/`DELETE` | `/projects/{id}` | CRUD. |

## Apps

| Method | Path | Notes |
|---|---|---|
| `GET`/`POST` | `/apps/?projectId=` | List + create. |
| `GET`/`PATCH`/`DELETE` | `/apps/{id}` | CRUD. |
| `POST` | `/apps/{id}/start\|stop\|restart` | Lifecycle. |
| `GET`/`POST` | `/apps/{id}/envs` | List + upsert. `value` is hidden if `isSecret`. |
| `DELETE` | `/apps/{id}/envs/{envId}` | Delete. |

## Deployments

| Method | Path | Notes |
|---|---|---|
| `GET` | `/apps/{id}/deployments/` | List, newest first. |
| `POST` | `/apps/{id}/deployments/` | Body `{sourceType, gitCommitSha?, artifactId?}`. Queues a build. |
| `POST` | `/apps/{id}/deployments/{depId}/rollback` | Instantly re-activates that deployment's kept build with its recorded env vars and settings (no rebuild). |
| `GET` | `/apps/{id}/deployments/{depId}/logs` | Persisted build logs. |

## Push to deploy

Git apps can deploy on every push through a webhook.

| Method | Path | Notes |
|---|---|---|
| `GET` | `/apps/{id}/webhook` | Any team member. `{configured, enabled, path, branch, lastDeliveryAt, lastDeliveryResult}`; never the secret. |
| `POST` | `/apps/{id}/webhook` | Admin. Creates the webhook or rotates its secret; returns `{path, branch, secret}`. The secret is only ever returned here. |
| `DELETE` | `/apps/{id}/webhook` | Admin. Removes it; deliveries are refused afterwards. |
| `PUT` | `/apps/{id}/webhook/status-token` | Admin. Body `{token}`. Turns on commit statuses (below). Stored encrypted, never returned. |
| `DELETE` | `/apps/{id}/webhook/status-token` | Admin. Turns commit statuses off. |
| `POST` | `/webhooks/apps/{id}` | Called by the repository host, not behind panel login. |

Deliveries are checked with the app's secret: GitHub and Gitea / Forgejo
sign the body (`X-Hub-Signature-256`), GitLab sends `X-Gitlab-Token`. An
unknown app, a removed webhook and a bad signature all get the same
`401 invalid_signature`.

A push to the app's branch (or, with none set, the repository's default
branch) queues a deployment of that commit (`202 {deploymentId}`). These
are acknowledged and skipped (`200 {ignored: "..."}`): pings, other
events, other branches, tags, deleted branches, a redelivered delivery id,
and pushes while a deployment is still queued (the build clones the
branch head when it starts, so it already includes them). Limit: 120
deliveries per minute per source, bodies up to 5 MB.

**Commit statuses.** With a status token set, each deployment queued by a
push is reported on that commit as `gisila-panel/deploy`: pending while
queued / building / deploying, then success or failure. The token needs
"Commit statuses: write" (GitHub fine-grained), `api` (GitLab) or
`write:repository` (Gitea / Forgejo). The status URL comes from the signed
push and is only used when it is https on the app's own git host (or
`api.` + it), so the token is never sent elsewhere. Set `PANEL_PUBLIC_URL`
(e.g. `https://panel.example.com`) to link each status to the app's page.
Failed posts are retried up to 5 times.

## Cron jobs

Scheduled commands per app, run like Console commands: as the app's Linux
user, in its directory, with its env vars and toolchain. Schedules are
5-field cron expressions (`*/15 * * * *`, `0 3 * * mon-fri`) or `@hourly`,
`@daily`, `@weekly`, `@monthly`, `@yearly`, in **UTC**.

| Method | Path | Notes |
|---|---|---|
| `GET` | `/apps/{id}/cron/` | Any team member. Jobs with `nextRunAt`, `lastRunAt`, `lastStatus`. |
| `GET` | `/apps/{id}/cron/preview?schedule=...` | The next 5 run times, or `400 invalid_schedule` with the reason. |
| `POST` | `/apps/{id}/cron/` | Developer. Body `{name, schedule, command, timeoutSeconds? (1-3600, default 300), enabled?}`. At most 20 per app. |
| `PATCH` | `/apps/{id}/cron/{jobId}` | Developer. Any of the same fields. |
| `DELETE` | `/apps/{id}/cron/{jobId}` | Developer. Deletes the job and its runs. |
| `POST` | `/apps/{id}/cron/{jobId}/run` | Developer. Runs it now; `409` if a run is still going. Returns the run, whose `execId` streams live output like the Console. |
| `GET` | `/apps/{id}/cron/{jobId}/runs` | Developer (output can hold secrets). The last 50 runs, newest first, with `status` (`running`, `succeeded`, `failed`, `timed_out`, `skipped`), `exitCode` and the last 200 lines of output. |

The worker fires due jobs every 30 seconds. A slot is claimed atomically,
so several workers never run it twice; slots missed while the worker was
down run once. A run is skipped while the previous one is still going, or
while the app has never been deployed. Runs lost to a worker restart are
marked failed after their timeout plus 5 minutes.

## Firewall

The host firewall (ufw), for **superusers**. The API only records a change;
the worker applies it through `gisila-agent firewall`, which is the
authority on what is safe:

- It refuses changes that would cut off SSH or the panel: blocking the
  host's SSH ports (22 plus any `Port` in `sshd_config`), 80, 443, or the
  port the request came in on, for everyone; blocking a source that
  contains the requester's IP; removing the last allow rule for one of
  those ports; and turning the firewall on while a rule blocks the
  requester. Turning it on first adds allow rules for SSH, 80 and 443.
- Every change is applied with a snapshot of the old rules and a rollback
  timer that runs outside the panel (a transient systemd timer). The
  requester's browser confirms the change automatically from any page of
  the panel once it is applied: that the confirmation gets through proves
  the panel is still reachable. If the requester doesn't reach the panel
  within 5 minutes (`FIREWALL_CONFIRM_MINUTES`, 1 to 10), the old rules come
  back.
- One change at a time (a rollback restores the rules from before its
  change, so it would undo later ones too). Only rules added from the panel
  can be removed here; rules from apps, databases or the shell are listed
  read-only.

| Method | Path | Notes |
|---|---|---|
| `GET` | `/firewall/` | `available`, `active`, `defaultIncoming`, `sshPorts`, `rules` (each with `action`, `proto`, `port`, `from`, `comment`, `families`, `origin`: `panel`, `base` or `other`), `refreshedAt`, `open` (the change in progress) and the last 20 changes. |
| `POST` | `/firewall/rules` | Body `{action: allow\|deny\|reject\|limit, proto?: tcp\|udp\|any, port?: "22" or "8000:8100", from?: "any", an IP or a CIDR, note?}`. Returns the change (`201`), or `409` while another is in progress. |
| `POST` | `/firewall/rules/remove` | Same body, matching a rule with `origin: panel`. |
| `POST` | `/firewall/enable`, `/firewall/disable` | Turn ufw on or off. |
| `GET` | `/firewall/changes/{id}` | `status`: `queued`, `applying`, `awaiting_confirmation`, `confirm_requested`, `revert_requested`, `applied`, `rolled_back` or `failed` (refused, with the reason in `error`). |
| `GET` | `/firewall/pending` | `{open}`: the change in progress, or null. Polled by every page. |
| `POST` | `/firewall/changes/{id}/confirm` | Only the requester, before `confirmBy`. |
| `POST` | `/firewall/changes/{id}/revert` | Put the old rules back now. |
| `POST` | `/firewall/refresh` | Read the firewall again (it is also read every minute). |

Docker's published ports bypass ufw.

## Domains

| Method | Path | Notes |
|---|---|---|
| `GET`/`POST` | `/apps/{id}/domains/` | List + add. |
| `POST` | `/apps/{id}/domains/{domainId}/ssl` | Queue Let's Encrypt issuance. |
| `DELETE` | `/apps/{id}/domains/{domainId}` | Remove. |

## Metrics

| Method | Path | Notes |
|---|---|---|
| `GET` | `/apps/{id}/metrics/?minutes=60` | Recent CPU/memory samples. |

## Security (personal)

| Method | Path | Notes |
|---|---|---|
| `GET`/`POST` | `/me/security/tokens` | List · issue a new `gsl_…` token (returned once). |
| `DELETE` | `/me/security/tokens/{id}` | Revoke. |
| `GET`/`POST` | `/me/security/ssh-keys` | List · add. |
| `DELETE` | `/me/security/ssh-keys/{id}` | Remove. |

## Real-time

| Path | Description |
|---|---|
| `WS  /ws/apps/{id}/logs` | Runtime logs streamed from journald → Redis → WebSocket. First frame must be `{token, appId}`. |
| `WS  /ws/apps/{id}/build-logs/{deploymentId}` | Build-time logs for a specific deployment. |

## Error envelope

Every non-2xx response is `application/json`:

```json
{
  "error": {
    "status": 409,
    "code": "email_taken",
    "message": "An account with this email already exists.",
    "details": null
  }
}
```

Validation failures (`400`) include a `details` map of `field → message`.

## Rate limits

Defaults:

- Global: **300 req/min** per IP.
- `POST /auth/login`: **60 req/min**; `POST /auth/login/mfa`: **30 req/min**.
- `/auth/totp/*` changes: **10 req/min**.

The limits are kept in Redis (`gisila-panel:rl:*`), so one budget per
client is shared by every API isolate. If Redis can't be reached, requests
are let through and a warning is logged, rather than the API failing; the
failed-login throttle above is separate.

Override per-route via `RouteConfig.rateLimit`.
