-- Per-domain mail hostname + DKIM/DMARC/DNS metadata for the independent mail
-- feature. Safe for fresh installs (columns may already exist from
-- schema.gisila.up.sql) and existing databases.

ALTER TABLE "mail_domains"
  ADD COLUMN IF NOT EXISTS "mail_hostname" VARCHAR(255);

ALTER TABLE "mail_domains"
  ADD COLUMN IF NOT EXISTS "dkim_selector" VARCHAR(255) DEFAULT 'gisila';

ALTER TABLE "mail_domains"
  ADD COLUMN IF NOT EXISTS "dkim_public_key" TEXT;

ALTER TABLE "mail_domains"
  ADD COLUMN IF NOT EXISTS "dmarc_policy" VARCHAR(255) DEFAULT 'none';

ALTER TABLE "mail_domains"
  ADD COLUMN IF NOT EXISTS "public_ip" VARCHAR(255);
