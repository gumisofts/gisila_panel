-- Add Celery deployment fields and static site serving fields to apps.
-- Safe for both fresh installs and existing databases (IF NOT EXISTS).

-- Celery fields
ALTER TABLE "apps" ADD COLUMN IF NOT EXISTS "celery_app"          VARCHAR(255);
ALTER TABLE "apps" ADD COLUMN IF NOT EXISTS "celery_worker_count" INTEGER;
ALTER TABLE "apps" ADD COLUMN IF NOT EXISTS "celery_concurrency"  INTEGER;
ALTER TABLE "apps" ADD COLUMN IF NOT EXISTS "celery_queues"       VARCHAR(255);
ALTER TABLE "apps" ADD COLUMN IF NOT EXISTS "celery_beat_enabled" BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE "apps" ADD COLUMN IF NOT EXISTS "celery_extra_args"   VARCHAR(255);

-- Static site fields
ALTER TABLE "apps" ADD COLUMN IF NOT EXISTS "static_root" VARCHAR(255);
ALTER TABLE "apps" ADD COLUMN IF NOT EXISTS "static_spa"  BOOLEAN NOT NULL DEFAULT FALSE;
