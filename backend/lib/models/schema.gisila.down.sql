-- gisila-generated migration: down
-- DO NOT EDIT - regenerate via `dart run build_runner build`

BEGIN;

ALTER TABLE "audit_logs" DROP CONSTRAINT IF EXISTS "audit_logs_actor_fkey";
ALTER TABLE "audit_logs" DROP CONSTRAINT IF EXISTS "audit_logs_team_fkey";
ALTER TABLE "mail_accounts" DROP CONSTRAINT IF EXISTS "mail_accounts_mail_domain_fkey";
ALTER TABLE "postgres_databases" DROP CONSTRAINT IF EXISTS "postgres_databases_instance_fkey";
ALTER TABLE "app_events" DROP CONSTRAINT IF EXISTS "app_events_app_fkey";
ALTER TABLE "app_events" DROP CONSTRAINT IF EXISTS "app_events_actor_fkey";
ALTER TABLE "metric_samples" DROP CONSTRAINT IF EXISTS "metric_samples_app_fkey";
ALTER TABLE "domains" DROP CONSTRAINT IF EXISTS "domains_app_fkey";
ALTER TABLE "build_logs" DROP CONSTRAINT IF EXISTS "build_logs_deployment_fkey";
ALTER TABLE "deployments" DROP CONSTRAINT IF EXISTS "deployments_app_fkey";
ALTER TABLE "deployments" DROP CONSTRAINT IF EXISTS "deployments_triggered_by_fkey";
ALTER TABLE "env_vars" DROP CONSTRAINT IF EXISTS "env_vars_app_fkey";
ALTER TABLE "apps" DROP CONSTRAINT IF EXISTS "apps_project_fkey";
ALTER TABLE "apps" DROP CONSTRAINT IF EXISTS "apps_deploy_key_fkey";
ALTER TABLE "projects" DROP CONSTRAINT IF EXISTS "projects_team_fkey";
ALTER TABLE "ssh_keys" DROP CONSTRAINT IF EXISTS "ssh_keys_user_fkey";
ALTER TABLE "api_tokens" DROP CONSTRAINT IF EXISTS "api_tokens_user_fkey";
ALTER TABLE "team_members" DROP CONSTRAINT IF EXISTS "team_members_team_fkey";
ALTER TABLE "team_members" DROP CONSTRAINT IF EXISTS "team_members_user_fkey";
ALTER TABLE "teams" DROP CONSTRAINT IF EXISTS "teams_owner_fkey";
DROP TABLE IF EXISTS "audit_logs" CASCADE;
DROP TABLE IF EXISTS "mail_accounts" CASCADE;
DROP TABLE IF EXISTS "mail_domains" CASCADE;
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
