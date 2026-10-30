-- Scheduled commands per app. The worker's CronScheduler fires due jobs
-- through the same exec path as the app console, as the app's own user.
-- Schedules are 5-field cron expressions evaluated in UTC.
--
-- NOTE: never put a semicolon character inside a comment in a migration.

CREATE TABLE IF NOT EXISTS "app_cron_jobs" (
  "id" BIGSERIAL PRIMARY KEY,
  "app_id" BIGINT NOT NULL REFERENCES "apps" ("id") ON DELETE CASCADE,
  "name" VARCHAR(100) NOT NULL,
  "schedule" VARCHAR(100) NOT NULL,
  "command" TEXT NOT NULL,
  "timeout_seconds" INTEGER NOT NULL DEFAULT 300,
  "enabled" BOOLEAN NOT NULL DEFAULT TRUE,
  "next_run_at" TIMESTAMP WITH TIME ZONE,
  "last_run_at" TIMESTAMP WITH TIME ZONE,
  "last_status" VARCHAR(20),
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  "updated_at" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "app_cron_jobs_app_id_idx"
  ON "app_cron_jobs" ("app_id");
CREATE INDEX IF NOT EXISTS "app_cron_jobs_due_idx"
  ON "app_cron_jobs" ("next_run_at") WHERE "enabled";

-- One row per run. status is running, succeeded, failed, timed_out or
-- skipped. output_tail keeps the end of the output after the live log
-- buffer in Redis has expired. The newest runs per job are kept.
CREATE TABLE IF NOT EXISTS "app_cron_runs" (
  "id" BIGSERIAL PRIMARY KEY,
  "job_id" BIGINT NOT NULL REFERENCES "app_cron_jobs" ("id") ON DELETE CASCADE,
  "exec_id" VARCHAR(64),
  "trigger" VARCHAR(20) NOT NULL DEFAULT 'schedule',
  "status" VARCHAR(20) NOT NULL,
  "exit_code" INTEGER,
  "output_tail" TEXT,
  "started_at" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  "finished_at" TIMESTAMP WITH TIME ZONE
);

CREATE INDEX IF NOT EXISTS "app_cron_runs_job_id_idx"
  ON "app_cron_runs" ("job_id", "id" DESC);
