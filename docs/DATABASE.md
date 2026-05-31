# Database schema

The schema is declared in [`backend/lib/models/schema.gisila.yaml`](../backend/lib/models/schema.gisila.yaml).
Run `dart run build_runner build` to regenerate the Dart models and SQL
migration files. Run `dart run gisila_orm:migrate up` to apply them.

## Entities

```
User ──< TeamMember >── Team ──< Project ──< App ──< Deployment ──< BuildLog
   │                                          │
   ├──< ApiToken                              ├──< EnvVar
   ├──< SshKey                                ├──< Domain
   └──< AuditLog                              ├──< MetricSample
                                              └──< AppEvent
```

### Identity & access

| Table | Purpose |
|---|---|
| `users` | Account record + password hash. |
| `teams` | Billing + project owner. Every user owns at least one. |
| `team_members` | `team × user` join with a role (`owner|admin|developer|viewer`). |
| `api_tokens` | Long-lived `gsl_…` tokens for CLI / CI access. Stored as SHA-256 hash + lookup prefix. |
| `ssh_keys` | OpenSSH public keys. Fingerprint is SHA256 of the key blob. |

### Projects & apps

| Table | Purpose |
|---|---|
| `projects` | A grouping of related apps within a team. |
| `apps` | A deployable service. Holds the runtime, source config, sandbox limits, and the immutable Linux primitives (`linux_user`, `work_dir`, `internal_port`). |
| `env_vars` | Per-app `KEY=value` pairs. `is_secret=true` hides the value in the UI; the worker still writes them into `<work_dir>/.env`. |

### Deployments & builds

| Table | Purpose |
|---|---|
| `deployments` | One row per `Deploy now` / git push / rollback. Lifecycle states: `queued → building → deploying → succeeded|failed`. |
| `build_logs` | Streaming output from the agent for each deployment. |

### Domains

| Table | Purpose |
|---|---|
| `domains` | Custom hostnames + SSL state. `ssl_status` mirrors the certbot lifecycle. |

### Observability

| Table | Purpose |
|---|---|
| `metric_samples` | CPU / memory / RSS samples, sampled by a future metrics collector (TBD). |
| `app_events` | Human-readable activity log per app. |
| `audit_logs` | Tenant-wide audit trail. |

## Conventions

- **Primary keys**: integer auto-increment via gisila_orm.
- **Naming**: `snake_case` in YAML and SQL, `camelCase` in Dart.
- **Timestamps**: every table has `created_at`; mutable rows also have `updated_at`.
- **Foreign keys**: declared with `references:`. `on_delete` defaults to
  `cascade` for child-of relationships and `set null` for nice-to-have
  links (e.g. `Deployment.triggered_by`).

## Migrations

```bash
# Generate Dart + SQL from schema.gisila.yaml
dart run build_runner build --delete-conflicting-outputs

# Forward migrate
dart run gisila_orm:migrate up

# Rollback the last batch
dart run gisila_orm:migrate down

# Diff two schemas (use when bumping major versions)
dart run gisila_orm:migrate diff \
  --old lib/models/schema.gisila.yaml.last \
  --new lib/models/schema.gisila.yaml \
  --name add_billing
```
