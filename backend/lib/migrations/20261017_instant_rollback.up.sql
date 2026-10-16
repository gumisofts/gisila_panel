-- Instant rollback: every deployment records which release directory it runs
-- from and a snapshot of the env vars + unit config it ran with, so a rollback
-- re-activates that release as it was instead of rebuilding the branch head
-- with today's configuration. apps.releases_to_keep bounds how many
-- successful releases stay on disk for that.
--
-- NOTE: never put a semicolon character inside a comment in a migration.

ALTER TABLE "apps" ADD COLUMN IF NOT EXISTS "releases_to_keep" INTEGER DEFAULT 5;
UPDATE "apps" SET "releases_to_keep" = 5 WHERE "releases_to_keep" IS NULL;

ALTER TABLE "deployments" ADD COLUMN IF NOT EXISTS "rollback_of_id" INTEGER;
ALTER TABLE "deployments" ADD COLUMN IF NOT EXISTS "release_id" VARCHAR(255);
ALTER TABLE "deployments" ADD COLUMN IF NOT EXISTS "deploy_config" TEXT;
