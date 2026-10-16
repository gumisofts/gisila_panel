ALTER TABLE "deployments" DROP COLUMN IF EXISTS "deploy_config";
ALTER TABLE "deployments" DROP COLUMN IF EXISTS "release_id";
ALTER TABLE "deployments" DROP COLUMN IF EXISTS "rollback_of_id";
ALTER TABLE "apps" DROP COLUMN IF EXISTS "releases_to_keep";
