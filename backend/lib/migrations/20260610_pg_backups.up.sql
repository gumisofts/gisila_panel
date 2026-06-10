-- Per-database PostgreSQL backups: recurring schedule config + backup artifacts.
-- Safe for both fresh installs (objects may already exist from
-- schema.gisila.up.sql) and existing databases.

CREATE TABLE IF NOT EXISTS "postgres_backup_schedules" (
  "id" BIGSERIAL PRIMARY KEY,
  "database_id" INTEGER NOT NULL UNIQUE
    REFERENCES "postgres_databases" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "enabled" BOOLEAN DEFAULT FALSE,
  "frequency" VARCHAR(255) DEFAULT 'daily',
  "hour" INTEGER DEFAULT 2,
  "minute" INTEGER DEFAULT 0,
  "weekday" INTEGER,
  "scope" VARCHAR(255) DEFAULT 'full',
  "keep_count" INTEGER DEFAULT 7,
  "next_run_at" TIMESTAMP WITH TIME ZONE,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL,
  "updated_at" TIMESTAMP WITH TIME ZONE
);

CREATE TABLE IF NOT EXISTS "postgres_backups" (
  "id" BIGSERIAL PRIMARY KEY,
  "database_id" INTEGER NOT NULL
    REFERENCES "postgres_databases" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "file_path" VARCHAR(255),
  "file_name" VARCHAR(255),
  "size_bytes" BIGINT,
  "scope" VARCHAR(255) DEFAULT 'full',
  "status" VARCHAR(255) DEFAULT 'pending',
  "trigger" VARCHAR(255) DEFAULT 'manual',
  "error_message" TEXT,
  "started_at" TIMESTAMP WITH TIME ZONE,
  "completed_at" TIMESTAMP WITH TIME ZONE,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE INDEX IF NOT EXISTS "ix_postgres_backups_database_id"
  ON "postgres_backups" ("database_id");
