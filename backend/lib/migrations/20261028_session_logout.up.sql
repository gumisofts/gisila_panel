-- Server-side sign-out of one session. A session JWT stays valid until it
-- expires, so signing out records the token's hash here until then. The
-- authenticator refuses any token listed. Rows past expires_at are swept on
-- each sign-out.
--
-- NOTE: never put a semicolon character inside a comment in a migration.

CREATE TABLE IF NOT EXISTS "revoked_sessions" (
  "token_hash" VARCHAR(64) PRIMARY KEY,
  "expires_at" TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE INDEX IF NOT EXISTS "revoked_sessions_expires_at_idx"
  ON "revoked_sessions" ("expires_at");
