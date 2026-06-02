ALTER TABLE "mail_domains" DROP COLUMN IF EXISTS "public_ip";
ALTER TABLE "mail_domains" DROP COLUMN IF EXISTS "dmarc_policy";
ALTER TABLE "mail_domains" DROP COLUMN IF EXISTS "dkim_public_key";
ALTER TABLE "mail_domains" DROP COLUMN IF EXISTS "dkim_selector";
ALTER TABLE "mail_domains" DROP COLUMN IF EXISTS "mail_hostname";
