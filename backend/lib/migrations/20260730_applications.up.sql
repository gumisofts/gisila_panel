-- Application Management: decouple runtime/language stacks from the panel.
--
-- Applications are installable/updatable/removable independently of the
-- panel itself. Seeds one row per historically-hardcoded runtime so existing
-- apps keep working unchanged, then backfills apps.application_id /
-- apps.deployment_mode from the existing apps.runtime column.

CREATE TABLE IF NOT EXISTS "applications" (
  "id" BIGSERIAL PRIMARY KEY,
  "key" VARCHAR(255) UNIQUE,
  "display_name" VARCHAR(255) NOT NULL,
  "deploy_modes" VARCHAR(255) NOT NULL,
  "default_deploy_mode" VARCHAR(255) NOT NULL,
  "default_version" VARCHAR(255),
  "default_build_command" VARCHAR(255),
  "default_start_command" VARCHAR(255),
  "status" VARCHAR(255) DEFAULT 'pending',
  "is_builtin" BOOLEAN DEFAULT TRUE,
  "error_message" TEXT,
  "installed_at" TIMESTAMP WITH TIME ZONE,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL,
  "updated_at" TIMESTAMP WITH TIME ZONE
);

ALTER TABLE "apps" ADD COLUMN IF NOT EXISTS "application_id" INTEGER;
ALTER TABLE "apps" ADD COLUMN IF NOT EXISTS "deployment_mode" VARCHAR(255);

ALTER TABLE "apps" DROP CONSTRAINT IF EXISTS "apps_application_fkey";
ALTER TABLE "apps" ADD CONSTRAINT "apps_application_fkey"
  FOREIGN KEY ("application_id") REFERENCES "applications" ("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

-- Seed the builtin catalog. Every row starts pre-installed (status =
-- 'installed') so existing installations keep deploying without any admin
-- action. New installs can still remove/reconfigure them from the panel.
-- NOTE: never put a semicolon character inside a comment in a migration.
-- The published gisila_orm 0.1.1 splits scripts on that character without
-- stripping comments first, so the rest of the line becomes a bogus
-- statement and the migration fails with a syntax error.
INSERT INTO "applications"
  ("key", "display_name", "deploy_modes", "default_deploy_mode",
   "default_build_command", "default_start_command", "status", "is_builtin",
   "installed_at", "created_at")
VALUES
  ('dart', 'Dart', 'build_execute', 'build_execute',
   'dart pub get && dart compile exe bin/server.dart -o build/app', NULL,
   'installed', TRUE, now(), now()),
  ('go', 'Go', 'build_execute', 'build_execute',
   'go build -o build/app ./...', NULL, 'installed', TRUE, now(), now()),
  ('rust', 'Rust', 'build_execute', 'build_execute',
   'cargo build --release', NULL, 'installed', TRUE, now(), now()),
  ('zig', 'Zig', 'build_execute', 'build_execute',
   NULL, NULL, 'installed', TRUE, now(), now()),
  ('bun', 'Bun', 'build_execute,direct_run', 'build_execute',
   'bun install', 'bun run start', 'installed', TRUE, now(), now()),
  ('node', 'Node.js', 'build_execute,direct_run', 'build_execute',
   'npm ci', 'node dist/index.js', 'installed', TRUE, now(), now()),
  ('python', 'Python', 'direct_run', 'direct_run',
   'python3 -m venv .venv && .venv/bin/pip install -r requirements.txt', NULL,
   'installed', TRUE, now(), now()),
  ('celery', 'Celery', 'build_execute', 'build_execute',
   NULL, NULL, 'installed', TRUE, now(), now()),
  ('static', 'Static Site', 'static_publish', 'static_publish',
   NULL, NULL, 'installed', TRUE, now(), now()),
  ('binary', 'Binary', 'direct_run', 'direct_run',
   NULL, NULL, 'installed', TRUE, now(), now())
ON CONFLICT ("key") DO NOTHING;

-- Backfill existing apps: point application_id at the matching catalog row
-- and default deployment_mode to that Application's default_deploy_mode.
UPDATE "apps" AS a
SET "application_id" = ap."id",
    "deployment_mode" = ap."default_deploy_mode"
FROM "applications" AS ap
WHERE ap."key" = a."runtime"
  AND a."application_id" IS NULL;
