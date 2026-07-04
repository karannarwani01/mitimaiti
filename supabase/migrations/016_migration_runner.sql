-- 016_migration_runner.sql
--
-- Bootstrap for the automated migration runner (backend/src/migrate.ts). This
-- is the ONLY migration that must be applied by hand (SQL editor) — it creates
-- the machinery the runner needs, so from 017 onwards migrations auto-apply on
-- deploy.
--
--   * schema_migrations  — tracks which files have been applied (exactly once)
--   * exec_migration_sql — runs a migration's DDL. SECURITY DEFINER, granted
--                          ONLY to service_role (the backend's key), never to
--                          anon/authenticated. The runner calls it via
--                          supabase-js, so no DB password / direct connection
--                          is needed.

CREATE TABLE IF NOT EXISTS schema_migrations (
  filename   TEXT PRIMARY KEY,
  applied_at TIMESTAMPTZ DEFAULT now()
);

CREATE OR REPLACE FUNCTION exec_migration_sql(sql text)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
AS $$
BEGIN
  EXECUTE sql;
END;
$$;

REVOKE ALL ON FUNCTION exec_migration_sql(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION exec_migration_sql(text) TO service_role;
