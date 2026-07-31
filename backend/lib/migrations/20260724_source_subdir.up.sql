-- Optional subdirectory within the repo to build/run the app from, so a
-- single git repo containing multiple projects (a monorepo) can be deployed
-- by pointing at just one of them.

ALTER TABLE "apps" ADD COLUMN IF NOT EXISTS "source_subdir" VARCHAR(255);
