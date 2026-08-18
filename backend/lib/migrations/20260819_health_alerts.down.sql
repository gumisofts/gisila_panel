-- Reverses 20260819_health_alerts.

ALTER TABLE "alert_events" DROP CONSTRAINT IF EXISTS "alert_events_application_fkey";
ALTER TABLE "alert_events" DROP CONSTRAINT IF EXISTS "alert_events_managed_service_fkey";
ALTER TABLE "alert_events" DROP COLUMN IF EXISTS "application_id";
ALTER TABLE "alert_events" DROP COLUMN IF EXISTS "managed_service_id";

ALTER TABLE "alert_rules" DROP CONSTRAINT IF EXISTS "alert_rules_application_fkey";
ALTER TABLE "alert_rules" DROP CONSTRAINT IF EXISTS "alert_rules_managed_service_fkey";
ALTER TABLE "alert_rules" DROP COLUMN IF EXISTS "application_id";
ALTER TABLE "alert_rules" DROP COLUMN IF EXISTS "managed_service_id";
