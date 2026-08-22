-- Reverses 20260822_alert_improvements.

ALTER TABLE "smtp_configs" DROP COLUMN IF EXISTS "alert_email";
