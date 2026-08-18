-- Extend alerting to mail / managed-service / runtime health, generalizing
-- the mail-stack health-check design to also cover Services and Runtimes.
-- See HealthMonitorWorker for the probes that feed these new alert scopes.
--
-- NOTE: never put a semicolon character inside a comment in a migration.

ALTER TABLE "alert_rules" ADD COLUMN IF NOT EXISTS "managed_service_id" BIGINT;
ALTER TABLE "alert_rules" ADD COLUMN IF NOT EXISTS "application_id" BIGINT;

ALTER TABLE "alert_rules" DROP CONSTRAINT IF EXISTS "alert_rules_managed_service_fkey";
ALTER TABLE "alert_rules" ADD CONSTRAINT "alert_rules_managed_service_fkey"
  FOREIGN KEY ("managed_service_id") REFERENCES "managed_services" ("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "alert_rules" DROP CONSTRAINT IF EXISTS "alert_rules_application_fkey";
ALTER TABLE "alert_rules" ADD CONSTRAINT "alert_rules_application_fkey"
  FOREIGN KEY ("application_id") REFERENCES "applications" ("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "alert_events" ADD COLUMN IF NOT EXISTS "managed_service_id" BIGINT;
ALTER TABLE "alert_events" ADD COLUMN IF NOT EXISTS "application_id" BIGINT;

ALTER TABLE "alert_events" DROP CONSTRAINT IF EXISTS "alert_events_managed_service_fkey";
ALTER TABLE "alert_events" ADD CONSTRAINT "alert_events_managed_service_fkey"
  FOREIGN KEY ("managed_service_id") REFERENCES "managed_services" ("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "alert_events" DROP CONSTRAINT IF EXISTS "alert_events_application_fkey";
ALTER TABLE "alert_events" ADD CONSTRAINT "alert_events_application_fkey"
  FOREIGN KEY ("application_id") REFERENCES "applications" ("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
