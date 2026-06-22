-- Per-database-role attributes (permissions) the panel can grant and change.
-- Stored as a JSON array of Postgres role attribute keywords, e.g.
-- ["CREATEDB","CREATEROLE"]. CREATEDB is what Prisma's shadow database /
-- `prisma migrate` requires. Safe for fresh installs and existing databases.

ALTER TABLE "postgres_databases"
  ADD COLUMN IF NOT EXISTS "role_attributes" TEXT DEFAULT '[]';
