-- Per-team resource quotas, set by a superuser. NULL means no limit.
-- Checked when an app is created, moved into the team, or its memory or CPU
-- limit is raised, against the sum over the team's apps.
--
-- NOTE: never put a semicolon character inside a comment in a migration.

ALTER TABLE "teams" ADD COLUMN IF NOT EXISTS "max_apps" INTEGER;
ALTER TABLE "teams" ADD COLUMN IF NOT EXISTS "max_memory_mb" INTEGER;
ALTER TABLE "teams" ADD COLUMN IF NOT EXISTS "max_cpu_percent" INTEGER;
