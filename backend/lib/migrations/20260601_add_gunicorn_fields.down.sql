ALTER TABLE "apps" DROP COLUMN IF EXISTS "gunicorn_workers";
ALTER TABLE "apps" DROP COLUMN IF EXISTS "gunicorn_threads";
ALTER TABLE "apps" DROP COLUMN IF EXISTS "gunicorn_timeout";
ALTER TABLE "apps" DROP COLUMN IF EXISTS "gunicorn_bind";
ALTER TABLE "apps" DROP COLUMN IF EXISTS "gunicorn_extra_args";
