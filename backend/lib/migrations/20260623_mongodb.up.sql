-- MongoDB as a managed NoSQL engine alongside PostgreSQL. Versioned, side-by-side
-- server instances on dedicated ports, each with authenticated databases/users,
-- backups, and recurring backup schedules. Mirrors the postgres_* tables.

CREATE TABLE IF NOT EXISTS "mongo_instances" (
  "id" BIGSERIAL PRIMARY KEY,
  "version" VARCHAR(255) NOT NULL,
  "display_name" VARCHAR(255) NOT NULL,
  "port" INTEGER NOT NULL UNIQUE,
  "status" VARCHAR(255) DEFAULT 'pending',
  "is_default" BOOLEAN DEFAULT FALSE,
  "is_public" BOOLEAN DEFAULT FALSE,
  "public_domain" VARCHAR(255),
  "root_password" VARCHAR(255),
  "monitor_password" VARCHAR(255),
  "data_directory" VARCHAR(255),
  "error_message" TEXT,
  "installed_at" TIMESTAMP WITH TIME ZONE,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL,
  "updated_at" TIMESTAMP WITH TIME ZONE
);

CREATE TABLE IF NOT EXISTS "mongo_databases" (
  "id" BIGSERIAL PRIMARY KEY,
  "instance_id" INTEGER NOT NULL
    REFERENCES "mongo_instances" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "db_name" VARCHAR(255) NOT NULL,
  "user_name" VARCHAR(255) NOT NULL,
  "password" VARCHAR(255) NOT NULL,
  "roles" TEXT DEFAULT '[]',
  "status" VARCHAR(255) DEFAULT 'pending',
  "error_message" TEXT,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL,
  "updated_at" TIMESTAMP WITH TIME ZONE
);

CREATE INDEX IF NOT EXISTS "ix_mongo_databases_instance_id"
  ON "mongo_databases" ("instance_id");

CREATE TABLE IF NOT EXISTS "mongo_backup_schedules" (
  "id" BIGSERIAL PRIMARY KEY,
  "database_id" INTEGER NOT NULL UNIQUE
    REFERENCES "mongo_databases" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
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

CREATE TABLE IF NOT EXISTS "mongo_backups" (
  "id" BIGSERIAL PRIMARY KEY,
  "database_id" INTEGER NOT NULL
    REFERENCES "mongo_databases" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
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

CREATE INDEX IF NOT EXISTS "ix_mongo_backups_database_id"
  ON "mongo_backups" ("database_id");
