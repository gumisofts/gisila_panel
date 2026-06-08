-- Add runtime version pins to apps.
-- Each column is only used by its respective runtime; all are nullable.

ALTER TABLE "apps" ADD COLUMN IF NOT EXISTS "node_version" VARCHAR(255);
ALTER TABLE "apps" ADD COLUMN IF NOT EXISTS "dart_version" VARCHAR(255);
ALTER TABLE "apps" ADD COLUMN IF NOT EXISTS "go_version"   VARCHAR(255);
ALTER TABLE "apps" ADD COLUMN IF NOT EXISTS "rust_version" VARCHAR(255);
ALTER TABLE "apps" ADD COLUMN IF NOT EXISTS "bun_version"  VARCHAR(255);
