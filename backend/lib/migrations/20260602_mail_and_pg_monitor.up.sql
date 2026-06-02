-- Mail server (virtual domains + mailboxes) and PostgreSQL monitor credentials.
-- Safe for both fresh installs (objects may already exist from
-- schema.gisila.up.sql) and existing databases.

ALTER TABLE "postgres_instances"
  ADD COLUMN IF NOT EXISTS "monitor_password" VARCHAR(255);

CREATE TABLE IF NOT EXISTS "mail_domains" (
  "id" BIGSERIAL PRIMARY KEY,
  "domain" VARCHAR(255) NOT NULL UNIQUE,
  "is_active" BOOLEAN DEFAULT TRUE,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE TABLE IF NOT EXISTS "mail_accounts" (
  "id" BIGSERIAL PRIMARY KEY,
  "mail_domain_id" INTEGER NOT NULL,
  "address" VARCHAR(255) NOT NULL UNIQUE,
  "password_hash" VARCHAR(255) NOT NULL,
  "quota_mb" INTEGER,
  "is_active" BOOLEAN DEFAULT TRUE,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL,
  "updated_at" TIMESTAMP WITH TIME ZONE
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'mail_accounts_mail_domain_fkey'
  ) THEN
    ALTER TABLE "mail_accounts"
      ADD CONSTRAINT "mail_accounts_mail_domain_fkey"
      FOREIGN KEY ("mail_domain_id") REFERENCES "mail_domains" ("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END$$;
