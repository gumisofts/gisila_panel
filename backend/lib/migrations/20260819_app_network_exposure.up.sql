-- Network exposure mode for Apps: 'web' (nginx + optional domain, current
-- default behavior), 'tcp' (direct port, no nginx/domain, opt-in publicly
-- reachable via the host firewall), 'internal' (no public exposure at all).
-- See docs/DEPLOYMENT_ENGINE.md.
ALTER TABLE "apps" ADD COLUMN IF NOT EXISTS "expose_mode" VARCHAR(255) DEFAULT 'web';
ALTER TABLE "apps" ADD COLUMN IF NOT EXISTS "publicly_reachable" BOOLEAN DEFAULT FALSE;

-- Backfill existing rows explicitly (DEFAULT only applies to new rows on some
-- Postgres versions' ADD COLUMN semantics for pre-existing rows it actually
-- does apply, but this keeps intent obvious and is a no-op cost-wise).
UPDATE "apps" SET "expose_mode" = 'web' WHERE "expose_mode" IS NULL;
UPDATE "apps" SET "publicly_reachable" = FALSE WHERE "publicly_reachable" IS NULL;
