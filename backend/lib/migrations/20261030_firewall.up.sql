-- Host firewall (ufw) changes made from the panel's Firewall page, and the
-- last firewall status the worker read from the host.
--
-- The API only records a change. The worker's FirewallWorker applies it
-- through gisila-agent, which snapshots the rules first and rolls them back
-- unless the requester's browser confirms the change within a time window
-- (proof that the panel can still be reached through the new rules).
--
-- status: queued, applying, awaiting_confirmation, confirm_requested,
-- revert_requested, applied, rolled_back or failed.
--
-- NOTE: never put a semicolon character inside a comment in a migration.

CREATE TABLE IF NOT EXISTS "firewall_changes" (
  "id" BIGSERIAL PRIMARY KEY,
  "op" VARCHAR(20) NOT NULL,
  "rule" JSONB,
  "status" VARCHAR(30) NOT NULL DEFAULT 'queued',
  "error" TEXT,
  "requested_by" BIGINT REFERENCES "users" ("id") ON DELETE SET NULL,
  "requester_ip" VARCHAR(64),
  "protect_ports" INTEGER[] NOT NULL DEFAULT '{}',
  "confirm_by" TIMESTAMP WITH TIME ZONE,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  "finished_at" TIMESTAMP WITH TIME ZONE
);

-- One change at a time: a rollback restores the rules from before its
-- change, so it would also undo any change made after it.
CREATE UNIQUE INDEX IF NOT EXISTS "firewall_changes_one_open_idx"
  ON "firewall_changes" ((TRUE))
  WHERE "status" IN ('queued', 'applying', 'awaiting_confirmation',
                     'confirm_requested', 'revert_requested');

CREATE TABLE IF NOT EXISTS "firewall_state" (
  "id" SMALLINT PRIMARY KEY DEFAULT 1 CHECK ("id" = 1),
  "state" JSONB NOT NULL DEFAULT '{}',
  "refreshed_at" TIMESTAMP WITH TIME ZONE,
  "refresh_requested_at" TIMESTAMP WITH TIME ZONE
);
