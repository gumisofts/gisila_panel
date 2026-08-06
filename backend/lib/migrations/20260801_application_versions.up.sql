-- Multi-version Application Management.
--
-- Until now an Application was a singleton: one row per runtime key, with a
-- single default_version scalar, so installing Python 3.12 and 3.11 side by
-- side was impossible from the panel even though pyenv/fnm/rustup on the host
-- have always supported it. This adds one row per installed version.
--
-- Unversioned Applications (static, binary, zig, celery) get no rows here and
-- keep being tracked by the applications row alone.
--
-- NOTE: never put a semicolon character inside a comment in a migration.
-- Older gisila_orm releases split scripts on that character without stripping
-- comments first, so the rest of the line becomes a bogus statement.

CREATE TABLE IF NOT EXISTS "application_versions" (
  "id" BIGSERIAL PRIMARY KEY,
  "application_id" BIGINT NOT NULL,
  "version" VARCHAR(255) NOT NULL,
  "status" VARCHAR(255) DEFAULT 'pending',
  "is_default" BOOLEAN DEFAULT FALSE,
  "error_message" TEXT,
  "installed_at" TIMESTAMP WITH TIME ZONE,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL,
  "updated_at" TIMESTAMP WITH TIME ZONE,
  CONSTRAINT "application_versions_application_fkey"
    FOREIGN KEY ("application_id") REFERENCES "applications" ("id")
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "application_versions_app_version_key"
    UNIQUE ("application_id", "version")
);

CREATE INDEX IF NOT EXISTS "application_versions_version_idx"
  ON "application_versions" ("version");

CREATE INDEX IF NOT EXISTS "application_versions_application_id_idx"
  ON "application_versions" ("application_id");

-- Backfill 1: the version each Application already pointed at becomes its
-- first installed version, and stays the default.
INSERT INTO "application_versions"
  ("application_id", "version", "status", "is_default", "installed_at",
   "created_at")
SELECT ap."id", ap."default_version", 'installed', TRUE,
       COALESCE(ap."installed_at", now()), now()
FROM "applications" AS ap
WHERE ap."default_version" IS NOT NULL
  AND ap."default_version" <> ''
ON CONFLICT ("application_id", "version") DO NOTHING;

-- Backfill 2: versions that apps already pin. Deploys install toolchains
-- lazily, so these are in all likelihood already on disk — recording them
-- means the panel reflects the host instead of claiming nothing is installed.
INSERT INTO "application_versions"
  ("application_id", "version", "status", "is_default", "installed_at",
   "created_at")
SELECT DISTINCT ap."id", v."version", 'installed', FALSE, now(), now()
FROM (
  SELECT 'python' AS "key", "python_version" AS "version" FROM "apps"
    WHERE "python_version" IS NOT NULL AND "python_version" <> ''
  UNION
  SELECT 'node', "node_version" FROM "apps"
    WHERE "node_version" IS NOT NULL AND "node_version" <> ''
  UNION
  SELECT 'dart', "dart_version" FROM "apps"
    WHERE "dart_version" IS NOT NULL AND "dart_version" <> ''
  UNION
  SELECT 'go', "go_version" FROM "apps"
    WHERE "go_version" IS NOT NULL AND "go_version" <> ''
  UNION
  SELECT 'rust', "rust_version" FROM "apps"
    WHERE "rust_version" IS NOT NULL AND "rust_version" <> ''
  UNION
  SELECT 'bun', "bun_version" FROM "apps"
    WHERE "bun_version" IS NOT NULL AND "bun_version" <> ''
) AS v
JOIN "applications" AS ap ON ap."key" = v."key"
ON CONFLICT ("application_id", "version") DO NOTHING;

-- Every Application that ended up with versions needs exactly one default.
-- Where backfill 1 did not supply one, promote the oldest backfilled row.
UPDATE "application_versions" AS av
SET "is_default" = TRUE
WHERE av."id" IN (
  SELECT MIN(candidate."id")
  FROM "application_versions" AS candidate
  WHERE NOT EXISTS (
    SELECT 1 FROM "application_versions" AS existing
    WHERE existing."application_id" = candidate."application_id"
      AND existing."is_default"
  )
  GROUP BY candidate."application_id"
);

-- Keep the denormalized pointer on applications in sync with the default row,
-- so the new-app wizard and apps service keep reading it unchanged.
UPDATE "applications" AS ap
SET "default_version" = av."version"
FROM "application_versions" AS av
WHERE av."application_id" = ap."id"
  AND av."is_default"
  AND (ap."default_version" IS NULL OR ap."default_version" = '');

-- Correct a claim the previous migration made that was never true. It seeded
-- every runtime as status 'installed', but installing Node/Dart/Go/Bun from
-- the catalog sent no version to the agent, whose install step then returned
-- without putting anything on disk. Those rows say installed while the host
-- has no toolchain. A versioned runtime with no versions is pending, not
-- installed -- deploys still install lazily, so nothing breaks either way.
--
-- The key list is spelled out rather than read from the catalog because a
-- migration is a snapshot of one moment, and must not change meaning later
-- when the catalog does.
UPDATE "applications"
SET "status" = 'pending'
WHERE "key" IN ('dart', 'go', 'rust', 'bun', 'node', 'python')
  AND "status" = 'installed'
  AND NOT EXISTS (
    SELECT 1 FROM "application_versions" AS av
    WHERE av."application_id" = "applications"."id"
  );
