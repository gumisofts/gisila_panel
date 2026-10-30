-- Push-to-deploy webhooks. One row per app that has a webhook. The secret
-- is sealed with SecretBox (column id app_webhooks.secret) because the
-- panel needs the plaintext to check GitHub and Gitea signatures.
--
-- NOTE: never put a semicolon character inside a comment in a migration.

CREATE TABLE IF NOT EXISTS "app_webhooks" (
  "app_id" BIGINT PRIMARY KEY REFERENCES "apps" ("id") ON DELETE CASCADE,
  "secret" TEXT NOT NULL,
  "enabled" BOOLEAN NOT NULL DEFAULT TRUE,
  "last_delivery_at" TIMESTAMP WITH TIME ZONE,
  "last_delivery_result" VARCHAR(255),
  -- Optional token for reporting deploy status back on the commit, sealed
  -- with SecretBox (column id app_webhooks.status_token).
  "status_token" TEXT,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  "updated_at" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Delivery ids already handled, so a redelivered webhook doesn't deploy
-- twice. Rows older than a week are swept as new deliveries arrive.
CREATE TABLE IF NOT EXISTS "app_webhook_deliveries" (
  "app_id" BIGINT NOT NULL REFERENCES "apps" ("id") ON DELETE CASCADE,
  "delivery_id" VARCHAR(128) NOT NULL,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  PRIMARY KEY ("app_id", "delivery_id")
);

CREATE INDEX IF NOT EXISTS "app_webhook_deliveries_created_at_idx"
  ON "app_webhook_deliveries" ("created_at");

-- Where to post the status of a deployment queued by a push: the
-- repository host's commit-status URL for that commit. The worker's
-- CommitStatusReporter posts each new state and records the last one sent.
CREATE TABLE IF NOT EXISTS "deployment_commit_statuses" (
  "deployment_id" BIGINT PRIMARY KEY REFERENCES "deployments" ("id") ON DELETE CASCADE,
  "app_id" BIGINT NOT NULL REFERENCES "apps" ("id") ON DELETE CASCADE,
  "host" VARCHAR(10) NOT NULL,
  "url" TEXT NOT NULL,
  "reported_state" VARCHAR(20),
  "attempts" INTEGER NOT NULL DEFAULT 0,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);
