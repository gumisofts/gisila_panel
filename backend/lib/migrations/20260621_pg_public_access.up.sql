-- Per-instance public exposure for PostgreSQL (TLS via Let's Encrypt).
ALTER TABLE "postgres_instances"
  ADD COLUMN IF NOT EXISTS "is_public" BOOLEAN DEFAULT FALSE;
ALTER TABLE "postgres_instances"
  ADD COLUMN IF NOT EXISTS "public_domain" VARCHAR(255);
