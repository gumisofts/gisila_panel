# API reference

The API is described by a live OpenAPI 3.1 spec served at
`/openapi.json`, with Swagger UI at `/docs` and ReDoc at `/redoc`. What
follows is a high-level map.

All endpoints accept either:

- `Authorization: Bearer <jwt>` — issued by `POST /auth/login` or
  `POST /auth/register`, or
- `Authorization: Bearer gsl_<…>` — a personal API token from
  `POST /me/security/tokens`, or
- `X-API-Token: gsl_<…>` — same as above, useful for CLI clients.

## Auth

| Method | Path | Body | Notes |
|---|---|---|---|
| `POST` | `/auth/register` | `{email, password, firstName?, lastName?}` | Public. Creates user + default team + JWT. |
| `POST` | `/auth/login` | `{email, password}` | Public. Returns JWT. |
| `GET`  | `/auth/me` | — | Auth required. |
| `POST` | `/auth/change-password` | `{oldPassword, newPassword}` | Auth required. |

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
| `POST` | `/apps/{id}/deployments/{depId}/rollback` | Re-queues the same artifact. |
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
- `POST /auth/login`: **60 req/min**.
- `POST /auth/register`: **20 req/min**.

Override per-route via `RouteConfig.rateLimit`.
