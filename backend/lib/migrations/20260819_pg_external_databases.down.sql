-- Reverting drops the external/provisioned distinction. Any discovered rows
-- left behind would become indistinguishable from panel-created databases, so
-- remove them first: they hold no credentials and describe databases the panel
-- never owned. Their backups and schedules cascade away with them; the dump
-- files on disk are cleaned up by the worker's normal retention path.
DELETE FROM "postgres_databases" WHERE "is_external" = TRUE;

ALTER TABLE "postgres_databases" DROP COLUMN IF EXISTS "is_external";
