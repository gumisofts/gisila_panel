-- Dedicated alert-recipient inbox on the panel-wide SMTP config, so firing
-- emails can go to an ops mailbox in addition to superuser / team inboxes.
-- CPU thresholds above 100% are a validation change only (no schema).
--
-- NOTE: never put a semicolon character inside a comment in a migration.

ALTER TABLE "smtp_configs" ADD COLUMN IF NOT EXISTS "alert_email" VARCHAR(255);
