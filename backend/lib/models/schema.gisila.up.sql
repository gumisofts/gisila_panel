-- gisila-generated migration: up
-- DO NOT EDIT - regenerate via `dart run build_runner build`

BEGIN;

CREATE TABLE "users" (
  "id" BIGSERIAL PRIMARY KEY,
  "first_name" VARCHAR(255),
  "last_name" VARCHAR(255),
  "email" VARCHAR(255) UNIQUE,
  "password" VARCHAR(255),
  "is_active" BOOLEAN DEFAULT TRUE,
  "is_staff" BOOLEAN DEFAULT FALSE,
  "is_superuser" BOOLEAN DEFAULT FALSE,
  "is_email_verified" BOOLEAN DEFAULT FALSE,
  "avatar_url" VARCHAR(255),
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL,
  "updated_at" TIMESTAMP WITH TIME ZONE
);


CREATE TABLE "teams" (
  "id" BIGSERIAL PRIMARY KEY,
  "name" VARCHAR(255) NOT NULL,
  "slug" VARCHAR(255) UNIQUE,
  "owner_id" INTEGER NOT NULL,
  "plan" VARCHAR(255) DEFAULT 'free',
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL
);


CREATE TABLE "team_members" (
  "id" BIGSERIAL PRIMARY KEY,
  "team_id" INTEGER NOT NULL,
  "user_id" INTEGER NOT NULL,
  "role" VARCHAR(255) DEFAULT 'developer',
  "invited_at" TIMESTAMP WITH TIME ZONE NOT NULL,
  "accepted_at" TIMESTAMP WITH TIME ZONE
);


CREATE TABLE "api_tokens" (
  "id" BIGSERIAL PRIMARY KEY,
  "user_id" INTEGER NOT NULL,
  "name" VARCHAR(255) NOT NULL,
  "token_hash" VARCHAR(255) UNIQUE,
  "prefix" VARCHAR(255),
  "last_used_at" TIMESTAMP WITH TIME ZONE,
  "expires_at" TIMESTAMP WITH TIME ZONE,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL
);


CREATE TABLE "ssh_keys" (
  "id" BIGSERIAL PRIMARY KEY,
  "user_id" INTEGER NOT NULL,
  "name" VARCHAR(255) NOT NULL,
  "algorithm" VARCHAR(255),
  "public_key" TEXT NOT NULL,
  "private_key" TEXT,
  "is_deploy_key" BOOLEAN DEFAULT FALSE,
  "fingerprint" VARCHAR(255) UNIQUE,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL
);


CREATE TABLE "projects" (
  "id" BIGSERIAL PRIMARY KEY,
  "team_id" INTEGER NOT NULL,
  "name" VARCHAR(255) NOT NULL,
  "slug" VARCHAR(255),
  "description" TEXT,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL
);


CREATE TABLE "apps" (
  "id" BIGSERIAL PRIMARY KEY,
  "project_id" INTEGER NOT NULL,
  "name" VARCHAR(255) NOT NULL,
  "slug" VARCHAR(255),
  "linux_user" VARCHAR(255) UNIQUE,
  "work_dir" VARCHAR(255) NOT NULL,
  "internal_port" INTEGER UNIQUE,
  "runtime" VARCHAR(255) NOT NULL,
  "source_type" VARCHAR(255) NOT NULL,
  "git_url" VARCHAR(255),
  "git_branch" VARCHAR(255),
  "build_command" VARCHAR(255),
  "start_command" VARCHAR(255),
  "health_check_path" VARCHAR(255),
  "deploy_key_id" INTEGER,
  "python_version" VARCHAR(255),
  "python_mode" VARCHAR(255),
  "wsgi_app" VARCHAR(255),
  "gunicorn_workers" INTEGER,
  "gunicorn_threads" INTEGER,
  "gunicorn_timeout" INTEGER,
  "gunicorn_bind" VARCHAR(255),
  "gunicorn_extra_args" VARCHAR(255),
  "memory_mb_limit" INTEGER DEFAULT 256,
  "cpu_quota_percent" INTEGER DEFAULT 50,
  "tasks_limit" INTEGER DEFAULT 100,
  "status" VARCHAR(255) DEFAULT 'created',
  "last_deployed_at" TIMESTAMP WITH TIME ZONE,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL,
  "updated_at" TIMESTAMP WITH TIME ZONE
);


CREATE TABLE "env_vars" (
  "id" BIGSERIAL PRIMARY KEY,
  "app_id" INTEGER NOT NULL,
  "name" VARCHAR(255) NOT NULL,
  "value" TEXT,
  "is_secret" BOOLEAN DEFAULT FALSE,
  "updated_at" TIMESTAMP WITH TIME ZONE NOT NULL
);


CREATE TABLE "deployments" (
  "id" BIGSERIAL PRIMARY KEY,
  "app_id" INTEGER NOT NULL,
  "triggered_by_id" INTEGER,
  "source_type" VARCHAR(255) NOT NULL,
  "git_commit_sha" VARCHAR(255),
  "artifact_path" VARCHAR(255),
  "status" VARCHAR(255) DEFAULT 'queued',
  "failure_reason" TEXT,
  "is_active" BOOLEAN DEFAULT FALSE,
  "started_at" TIMESTAMP WITH TIME ZONE,
  "finished_at" TIMESTAMP WITH TIME ZONE,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL
);


CREATE TABLE "build_logs" (
  "id" BIGSERIAL PRIMARY KEY,
  "deployment_id" INTEGER NOT NULL,
  "line" TEXT NOT NULL,
  "stream" VARCHAR(255) DEFAULT 'stdout',
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL
);


CREATE TABLE "domains" (
  "id" BIGSERIAL PRIMARY KEY,
  "app_id" INTEGER NOT NULL,
  "hostname" VARCHAR(255) UNIQUE,
  "is_primary" BOOLEAN DEFAULT FALSE,
  "is_verified" BOOLEAN DEFAULT FALSE,
  "verification_token" VARCHAR(255),
  "ssl_status" VARCHAR(255) DEFAULT 'none',
  "ssl_expires_at" TIMESTAMP WITH TIME ZONE,
  "ssl_issuer" VARCHAR(255),
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL
);


CREATE TABLE "metric_samples" (
  "id" BIGSERIAL PRIMARY KEY,
  "app_id" INTEGER NOT NULL,
  "cpu_percent" INTEGER DEFAULT 0,
  "mem_bytes" INTEGER DEFAULT 0,
  "rss_bytes" INTEGER DEFAULT 0,
  "sampled_at" TIMESTAMP WITH TIME ZONE NOT NULL
);


CREATE TABLE "app_events" (
  "id" BIGSERIAL PRIMARY KEY,
  "app_id" INTEGER NOT NULL,
  "actor_id" INTEGER,
  "kind" VARCHAR(255) NOT NULL,
  "message" TEXT,
  "data" TEXT,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL
);


CREATE TABLE "managed_services" (
  "id" BIGSERIAL PRIMARY KEY,
  "service_type" VARCHAR(255) NOT NULL,
  "display_name" VARCHAR(255) NOT NULL,
  "status" VARCHAR(255) DEFAULT 'pending',
  "config" TEXT DEFAULT '{}',
  "error_message" TEXT,
  "installed_at" TIMESTAMP WITH TIME ZONE,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL,
  "updated_at" TIMESTAMP WITH TIME ZONE
);


CREATE TABLE "postgres_instances" (
  "id" BIGSERIAL PRIMARY KEY,
  "version" INTEGER NOT NULL,
  "display_name" VARCHAR(255) NOT NULL,
  "port" INTEGER NOT NULL UNIQUE,
  "status" VARCHAR(255) DEFAULT 'pending',
  "is_default" BOOLEAN DEFAULT FALSE,
  "monitor_password" VARCHAR(255),
  "data_directory" VARCHAR(255),
  "error_message" TEXT,
  "installed_at" TIMESTAMP WITH TIME ZONE,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL,
  "updated_at" TIMESTAMP WITH TIME ZONE
);


CREATE TABLE "postgres_databases" (
  "id" BIGSERIAL PRIMARY KEY,
  "instance_id" INTEGER NOT NULL,
  "db_name" VARCHAR(255) NOT NULL,
  "role_name" VARCHAR(255) NOT NULL,
  "password" VARCHAR(255) NOT NULL,
  "extensions" TEXT DEFAULT '[]',
  "status" VARCHAR(255) DEFAULT 'pending',
  "error_message" TEXT,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL,
  "updated_at" TIMESTAMP WITH TIME ZONE
);


CREATE TABLE "mail_domains" (
  "id" BIGSERIAL PRIMARY KEY,
  "domain" VARCHAR(255) NOT NULL UNIQUE,
  "mail_hostname" VARCHAR(255),
  "dkim_selector" VARCHAR(255) DEFAULT 'gisila',
  "dkim_public_key" TEXT,
  "dmarc_policy" VARCHAR(255) DEFAULT 'none',
  "public_ip" VARCHAR(255),
  "is_active" BOOLEAN DEFAULT TRUE,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL
);


CREATE TABLE "mail_accounts" (
  "id" BIGSERIAL PRIMARY KEY,
  "mail_domain_id" INTEGER NOT NULL,
  "address" VARCHAR(255) NOT NULL UNIQUE,
  "password_hash" VARCHAR(255) NOT NULL,
  "quota_mb" INTEGER,
  "is_active" BOOLEAN DEFAULT TRUE,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL,
  "updated_at" TIMESTAMP WITH TIME ZONE
);


CREATE TABLE "audit_logs" (
  "id" BIGSERIAL PRIMARY KEY,
  "actor_id" INTEGER,
  "team_id" INTEGER,
  "action" VARCHAR(255) NOT NULL,
  "target_type" VARCHAR(255),
  "target_id" VARCHAR(255),
  "ip_address" VARCHAR(255),
  "user_agent" VARCHAR(255),
  "data" TEXT,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL
);


ALTER TABLE "teams" ADD CONSTRAINT "teams_owner_fkey" FOREIGN KEY ("owner_id") REFERENCES "users" ("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "team_members" ADD CONSTRAINT "team_members_team_fkey" FOREIGN KEY ("team_id") REFERENCES "teams" ("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "team_members" ADD CONSTRAINT "team_members_user_fkey" FOREIGN KEY ("user_id") REFERENCES "users" ("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "api_tokens" ADD CONSTRAINT "api_tokens_user_fkey" FOREIGN KEY ("user_id") REFERENCES "users" ("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "ssh_keys" ADD CONSTRAINT "ssh_keys_user_fkey" FOREIGN KEY ("user_id") REFERENCES "users" ("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "projects" ADD CONSTRAINT "projects_team_fkey" FOREIGN KEY ("team_id") REFERENCES "teams" ("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "apps" ADD CONSTRAINT "apps_project_fkey" FOREIGN KEY ("project_id") REFERENCES "projects" ("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "apps" ADD CONSTRAINT "apps_deploy_key_fkey" FOREIGN KEY ("deploy_key_id") REFERENCES "ssh_keys" ("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "env_vars" ADD CONSTRAINT "env_vars_app_fkey" FOREIGN KEY ("app_id") REFERENCES "apps" ("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "deployments" ADD CONSTRAINT "deployments_app_fkey" FOREIGN KEY ("app_id") REFERENCES "apps" ("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "deployments" ADD CONSTRAINT "deployments_triggered_by_fkey" FOREIGN KEY ("triggered_by_id") REFERENCES "users" ("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "build_logs" ADD CONSTRAINT "build_logs_deployment_fkey" FOREIGN KEY ("deployment_id") REFERENCES "deployments" ("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "domains" ADD CONSTRAINT "domains_app_fkey" FOREIGN KEY ("app_id") REFERENCES "apps" ("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "metric_samples" ADD CONSTRAINT "metric_samples_app_fkey" FOREIGN KEY ("app_id") REFERENCES "apps" ("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "app_events" ADD CONSTRAINT "app_events_app_fkey" FOREIGN KEY ("app_id") REFERENCES "apps" ("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "app_events" ADD CONSTRAINT "app_events_actor_fkey" FOREIGN KEY ("actor_id") REFERENCES "users" ("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "postgres_databases" ADD CONSTRAINT "postgres_databases_instance_fkey" FOREIGN KEY ("instance_id") REFERENCES "postgres_instances" ("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "mail_accounts" ADD CONSTRAINT "mail_accounts_mail_domain_fkey" FOREIGN KEY ("mail_domain_id") REFERENCES "mail_domains" ("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "audit_logs" ADD CONSTRAINT "audit_logs_actor_fkey" FOREIGN KEY ("actor_id") REFERENCES "users" ("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "audit_logs" ADD CONSTRAINT "audit_logs_team_fkey" FOREIGN KEY ("team_id") REFERENCES "teams" ("id") ON DELETE SET NULL ON UPDATE CASCADE;

CREATE INDEX "idx_api_tokens_prefix" ON "api_tokens" ("prefix");

CREATE INDEX "idx_projects_slug" ON "projects" ("slug");

CREATE INDEX "idx_apps_slug" ON "apps" ("slug");

CREATE INDEX "idx_managed_services_service_type" ON "managed_services" ("service_type");

COMMIT;
