-- Roll back the initial base schema. DROP ... CASCADE removes each table's
-- foreign keys with it, so the drops are order-independent and safe even if an
-- incremental down migration already removed some of these tables.

BEGIN;

DROP TABLE IF EXISTS "audit_logs" CASCADE;
DROP TABLE IF EXISTS "mail_accounts" CASCADE;
DROP TABLE IF EXISTS "mail_domains" CASCADE;
DROP TABLE IF EXISTS "postgres_backups" CASCADE;
DROP TABLE IF EXISTS "postgres_backup_schedules" CASCADE;
DROP TABLE IF EXISTS "postgres_databases" CASCADE;
DROP TABLE IF EXISTS "postgres_instances" CASCADE;
DROP TABLE IF EXISTS "managed_services" CASCADE;
DROP TABLE IF EXISTS "app_events" CASCADE;
DROP TABLE IF EXISTS "metric_samples" CASCADE;
DROP TABLE IF EXISTS "domains" CASCADE;
DROP TABLE IF EXISTS "build_logs" CASCADE;
DROP TABLE IF EXISTS "deployments" CASCADE;
DROP TABLE IF EXISTS "env_vars" CASCADE;
DROP TABLE IF EXISTS "apps" CASCADE;
DROP TABLE IF EXISTS "projects" CASCADE;
DROP TABLE IF EXISTS "ssh_keys" CASCADE;
DROP TABLE IF EXISTS "api_tokens" CASCADE;
DROP TABLE IF EXISTS "team_members" CASCADE;
DROP TABLE IF EXISTS "teams" CASCADE;
DROP TABLE IF EXISTS "users" CASCADE;

COMMIT;
