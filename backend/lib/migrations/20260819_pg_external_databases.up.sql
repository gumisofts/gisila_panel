-- Track databases that already existed on a cluster instead of ignoring them.
--
-- A database created with psql (or by another tool, or an older panel) has no
-- postgres_databases row, and both postgres_backups and
-- postgres_backup_schedules key off that row — so until now such a database
-- could not be backed up or scheduled at all. Discovery inserts a row flagged
-- is_external, which grants backups while withholding every write the panel has
-- no mandate for: restore, drop and ALTER ROLE.
--
-- Existing rows were all provisioned by the panel, so FALSE is the correct
-- backfill for them.

ALTER TABLE "postgres_databases"
  ADD COLUMN IF NOT EXISTS "is_external" BOOLEAN DEFAULT FALSE;

UPDATE "postgres_databases" SET "is_external" = FALSE WHERE "is_external" IS NULL;
