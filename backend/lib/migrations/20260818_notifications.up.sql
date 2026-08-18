-- Notifications & alerting.
--
-- Threshold-based alerting on whole-host resources, per-app quota usage, and
-- managed database health, delivered via the in-panel notification inbox and
-- (optionally) email through a panel-wide SMTP config. See the comment block
-- above these models in schema.gisila.yaml for the full design.
--
-- NOTE: never put a semicolon character inside a comment in a migration.

CREATE TABLE IF NOT EXISTS "smtp_configs" (
  "id" BIGSERIAL PRIMARY KEY,
  "smtp_host" VARCHAR(255),
  "smtp_port" INTEGER DEFAULT 587,
  "smtp_username" VARCHAR(255),
  "smtp_password" VARCHAR(255),
  "smtp_security" VARCHAR(255) DEFAULT 'starttls',
  "from_email" VARCHAR(255),
  "from_name" VARCHAR(255) DEFAULT 'Gisila Panel',
  "email_enabled" BOOLEAN DEFAULT FALSE,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL,
  "updated_at" TIMESTAMP WITH TIME ZONE
);

CREATE TABLE IF NOT EXISTS "alert_rules" (
  "id" BIGSERIAL PRIMARY KEY,
  "scope" VARCHAR(255) NOT NULL,
  "app_id" BIGINT,
  "postgres_instance_id" BIGINT,
  "mongo_instance_id" BIGINT,
  "metric" VARCHAR(255) NOT NULL,
  "comparison" VARCHAR(255) DEFAULT 'gte',
  "threshold_percent" INTEGER,
  "severity" VARCHAR(255) DEFAULT 'warning',
  "cooldown_minutes" INTEGER DEFAULT 15,
  "enabled" BOOLEAN DEFAULT TRUE,
  "notify_email" BOOLEAN DEFAULT TRUE,
  "last_triggered_at" TIMESTAMP WITH TIME ZONE,
  "created_by_id" BIGINT,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL,
  "updated_at" TIMESTAMP WITH TIME ZONE,
  CONSTRAINT "alert_rules_app_fkey"
    FOREIGN KEY ("app_id") REFERENCES "apps" ("id")
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "alert_rules_postgres_instance_fkey"
    FOREIGN KEY ("postgres_instance_id") REFERENCES "postgres_instances" ("id")
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "alert_rules_mongo_instance_fkey"
    FOREIGN KEY ("mongo_instance_id") REFERENCES "mongo_instances" ("id")
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "alert_rules_created_by_fkey"
    FOREIGN KEY ("created_by_id") REFERENCES "users" ("id")
    ON DELETE SET NULL ON UPDATE CASCADE
);

CREATE INDEX IF NOT EXISTS "idx_alert_rules_scope" ON "alert_rules" ("scope");

CREATE TABLE IF NOT EXISTS "alert_events" (
  "id" BIGSERIAL PRIMARY KEY,
  "rule_id" BIGINT NOT NULL,
  "scope" VARCHAR(255) NOT NULL,
  "app_id" BIGINT,
  "postgres_instance_id" BIGINT,
  "mongo_instance_id" BIGINT,
  "metric" VARCHAR(255) NOT NULL,
  "observed_percent" INTEGER,
  "threshold_percent" INTEGER,
  "severity" VARCHAR(255) DEFAULT 'warning',
  "message" TEXT NOT NULL,
  "status" VARCHAR(255) DEFAULT 'firing',
  "resolved_at" TIMESTAMP WITH TIME ZONE,
  "email_sent_at" TIMESTAMP WITH TIME ZONE,
  "email_error" TEXT,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL,
  CONSTRAINT "alert_events_rule_fkey"
    FOREIGN KEY ("rule_id") REFERENCES "alert_rules" ("id")
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "alert_events_app_fkey"
    FOREIGN KEY ("app_id") REFERENCES "apps" ("id")
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "alert_events_postgres_instance_fkey"
    FOREIGN KEY ("postgres_instance_id") REFERENCES "postgres_instances" ("id")
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "alert_events_mongo_instance_fkey"
    FOREIGN KEY ("mongo_instance_id") REFERENCES "mongo_instances" ("id")
    ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX IF NOT EXISTS "idx_alert_events_rule_id" ON "alert_events" ("rule_id");
CREATE INDEX IF NOT EXISTS "idx_alert_events_status" ON "alert_events" ("status");

CREATE TABLE IF NOT EXISTS "notifications" (
  "id" BIGSERIAL PRIMARY KEY,
  "user_id" BIGINT NOT NULL,
  "event_id" BIGINT,
  "title" VARCHAR(255) NOT NULL,
  "body" TEXT,
  "level" VARCHAR(255) DEFAULT 'warning',
  "read_at" TIMESTAMP WITH TIME ZONE,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL,
  CONSTRAINT "notifications_user_fkey"
    FOREIGN KEY ("user_id") REFERENCES "users" ("id")
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "notifications_event_fkey"
    FOREIGN KEY ("event_id") REFERENCES "alert_events" ("id")
    ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX IF NOT EXISTS "idx_notifications_user_id" ON "notifications" ("user_id");
CREATE INDEX IF NOT EXISTS "idx_notifications_user_read" ON "notifications" ("user_id", "read_at");
