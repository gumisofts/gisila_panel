-- Revert Celery and static site fields from apps.

ALTER TABLE "apps" DROP COLUMN IF EXISTS "celery_app";
ALTER TABLE "apps" DROP COLUMN IF EXISTS "celery_worker_count";
ALTER TABLE "apps" DROP COLUMN IF EXISTS "celery_concurrency";
ALTER TABLE "apps" DROP COLUMN IF EXISTS "celery_queues";
ALTER TABLE "apps" DROP COLUMN IF EXISTS "celery_beat_enabled";
ALTER TABLE "apps" DROP COLUMN IF EXISTS "celery_extra_args";
ALTER TABLE "apps" DROP COLUMN IF EXISTS "static_root";
ALTER TABLE "apps" DROP COLUMN IF EXISTS "static_spa";
