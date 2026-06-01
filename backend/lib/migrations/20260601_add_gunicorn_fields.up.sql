-- Add configurable gunicorn tuning fields to apps.
-- Safe for both fresh installs (columns may already exist from schema.gisila.up.sql)
-- and existing databases.

ALTER TABLE "apps" ADD COLUMN IF NOT EXISTS "gunicorn_workers" INTEGER;
ALTER TABLE "apps" ADD COLUMN IF NOT EXISTS "gunicorn_threads" INTEGER;
ALTER TABLE "apps" ADD COLUMN IF NOT EXISTS "gunicorn_timeout" INTEGER;
ALTER TABLE "apps" ADD COLUMN IF NOT EXISTS "gunicorn_bind" VARCHAR(255);
ALTER TABLE "apps" ADD COLUMN IF NOT EXISTS "gunicorn_extra_args" VARCHAR(255);
