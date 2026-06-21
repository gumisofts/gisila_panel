-- Public URL for the MinIO web console (served by its own nginx vhost).
ALTER TABLE "storage_providers"
  ADD COLUMN IF NOT EXISTS "console_url" VARCHAR(255);
