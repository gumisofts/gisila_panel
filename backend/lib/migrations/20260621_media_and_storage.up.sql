-- Media (Model A) + object storage (Model B).
-- Safe for fresh installs (objects may already exist from schema.gisila.up.sql)
-- and existing databases.

-- ── Model A: per-app local disk media ────────────────────────────────────────
ALTER TABLE "apps"
  ADD COLUMN IF NOT EXISTS "media_enabled" BOOLEAN DEFAULT FALSE;
ALTER TABLE "apps"
  ADD COLUMN IF NOT EXISTS "media_max_upload_mb" INTEGER DEFAULT 25;

-- ── Model B: S3-compatible object storage ────────────────────────────────────
CREATE TABLE IF NOT EXISTS "storage_providers" (
  "id" BIGSERIAL PRIMARY KEY,
  "kind" VARCHAR(255) NOT NULL,
  "display_name" VARCHAR(255) NOT NULL,
  "endpoint" VARCHAR(255) NOT NULL,
  "region" VARCHAR(255) DEFAULT 'us-east-1',
  "public_url" VARCHAR(255),
  "access_key" VARCHAR(255) NOT NULL,
  "secret_key" VARCHAR(255) NOT NULL,
  "force_path_style" BOOLEAN DEFAULT TRUE,
  "console_port" INTEGER,
  "status" VARCHAR(255) DEFAULT 'pending',
  "error_message" TEXT,
  "installed_at" TIMESTAMP WITH TIME ZONE,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL,
  "updated_at" TIMESTAMP WITH TIME ZONE
);

CREATE INDEX IF NOT EXISTS "ix_storage_providers_kind"
  ON "storage_providers" ("kind");

CREATE TABLE IF NOT EXISTS "storage_buckets" (
  "id" BIGSERIAL PRIMARY KEY,
  "provider_id" INTEGER NOT NULL
    REFERENCES "storage_providers" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "bucket_name" VARCHAR(255) NOT NULL,
  "access_key" VARCHAR(255) NOT NULL,
  "secret_key" VARCHAR(255) NOT NULL,
  "is_public" BOOLEAN DEFAULT FALSE,
  "status" VARCHAR(255) DEFAULT 'pending',
  "error_message" TEXT,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL,
  "updated_at" TIMESTAMP WITH TIME ZONE
);

CREATE INDEX IF NOT EXISTS "ix_storage_buckets_provider_id"
  ON "storage_buckets" ("provider_id");

CREATE TABLE IF NOT EXISTS "app_storage_links" (
  "id" BIGSERIAL PRIMARY KEY,
  "app_id" INTEGER NOT NULL
    REFERENCES "apps" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "bucket_id" INTEGER NOT NULL
    REFERENCES "storage_buckets" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
  "env_prefix" VARCHAR(255) DEFAULT 'S3',
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE INDEX IF NOT EXISTS "ix_app_storage_links_app_id"
  ON "app_storage_links" ("app_id");
CREATE INDEX IF NOT EXISTS "ix_app_storage_links_bucket_id"
  ON "app_storage_links" ("bucket_id");
