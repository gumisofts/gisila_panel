-- Reverses 20260801_application_versions.
--
-- applications.default_version survives the drop, so each Application falls
-- back to the single-version behaviour it had before, pinned to whichever
-- version was marked default.

DROP INDEX IF EXISTS "application_versions_application_id_idx";
DROP INDEX IF EXISTS "application_versions_version_idx";
DROP TABLE IF EXISTS "application_versions";
