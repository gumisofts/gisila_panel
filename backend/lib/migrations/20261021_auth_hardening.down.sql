-- Reverses 20261021_auth_hardening.

DROP TABLE IF EXISTS "user_totps";
ALTER TABLE "users" DROP COLUMN IF EXISTS "sessions_valid_after";
