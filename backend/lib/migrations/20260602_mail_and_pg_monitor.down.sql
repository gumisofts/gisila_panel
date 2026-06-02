DROP TABLE IF EXISTS "mail_accounts";
DROP TABLE IF EXISTS "mail_domains";
ALTER TABLE "postgres_instances" DROP COLUMN IF EXISTS "monitor_password";
