ALTER TABLE "apps" DROP CONSTRAINT IF EXISTS "apps_application_fkey";
ALTER TABLE "apps" DROP COLUMN IF EXISTS "application_id";
ALTER TABLE "apps" DROP COLUMN IF EXISTS "deployment_mode";

DROP TABLE IF EXISTS "applications";
