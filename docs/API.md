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

These limits are counted per API isolate (one per CPU). The failed-login
throttle above is shared across all of them.

Override per-route via `RouteConfig.rateLimit`.
