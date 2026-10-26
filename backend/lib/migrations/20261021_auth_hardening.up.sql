-- Auth hardening: server-side session revocation and TOTP second factor.
-- users.sessions_valid_after rejects session JWTs issued before it. The
-- user_totps table holds the TOTP secret apart from users so that no user
-- serialization can carry it.
--
-- NOTE: never put a semicolon character inside a comment in a migration.

ALTER TABLE "users" ADD COLUMN IF NOT EXISTS "sessions_valid_after" TIMESTAMP WITH TIME ZONE;

CREATE TABLE IF NOT EXISTS "user_totps" (
  "id" BIGSERIAL PRIMARY KEY,
  "user_id" BIGINT NOT NULL UNIQUE,
  "secret" VARCHAR(255) NOT NULL,
  "confirmed_at" TIMESTAMP WITH TIME ZONE,
  "last_used_step" INTEGER,
  "recovery_codes" TEXT,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL
);

ALTER TABLE "user_totps" DROP CONSTRAINT IF EXISTS "user_totps_user_fkey";
ALTER TABLE "user_totps" ADD CONSTRAINT "user_totps_user_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users" ("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
