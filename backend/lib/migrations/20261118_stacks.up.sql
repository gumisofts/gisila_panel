-- Stacks group the apps of a project that belong together and give them one
-- shared set of env vars. An app in a stack is deployed with the stack's vars
-- plus its own, and its own value wins when both define a name.
--
-- NOTE: never put a semicolon character inside a comment in a migration.

CREATE TABLE IF NOT EXISTS "stacks" (
  "id" BIGSERIAL PRIMARY KEY,
  "project_id" BIGINT NOT NULL REFERENCES "projects" ("id") ON DELETE CASCADE,
  "name" VARCHAR(255) NOT NULL,
  "slug" VARCHAR(255),
  "description" TEXT,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  "updated_at" TIMESTAMP WITH TIME ZONE
);

CREATE INDEX IF NOT EXISTS "stacks_project_id_idx" ON "stacks" ("project_id");

CREATE TABLE IF NOT EXISTS "stack_env_vars" (
  "id" BIGSERIAL PRIMARY KEY,
  "stack_id" BIGINT NOT NULL REFERENCES "stacks" ("id") ON DELETE CASCADE,
  "name" VARCHAR(255) NOT NULL,
  "value" TEXT,
  "is_secret" BOOLEAN DEFAULT FALSE,
  "updated_at" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE ("stack_id", "name")
);

ALTER TABLE "apps"
  ADD COLUMN IF NOT EXISTS "stack_id" BIGINT
  REFERENCES "stacks" ("id") ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS "apps_stack_id_idx" ON "apps" ("stack_id");
