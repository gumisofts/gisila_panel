-- Rollback media (Model A) + object storage (Model B).
DROP TABLE IF EXISTS "app_storage_links";
DROP TABLE IF EXISTS "storage_buckets";
DROP TABLE IF EXISTS "storage_providers";

ALTER TABLE "apps" DROP COLUMN IF EXISTS "media_max_upload_mb";
ALTER TABLE "apps" DROP COLUMN IF EXISTS "media_enabled";
