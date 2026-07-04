-- 015_error_log.sql
--
-- Zero-setup error tracking: instead of an external service (Sentry) that needs
-- an account + DSN, capture 5xx / unhandled server errors into a table you can
-- just open in the Supabase dashboard. The backend writes here best-effort from
-- the global error handler. Sentry stays wired too (dormant until SENTRY_DSN is
-- set) — this is the always-on, no-account version.

CREATE TABLE IF NOT EXISTS error_log (
  id          BIGSERIAL PRIMARY KEY,
  created_at  TIMESTAMPTZ DEFAULT now(),
  code        TEXT,
  status_code INT,
  method      TEXT,
  path        TEXT,
  message     TEXT,
  stack       TEXT
);

CREATE INDEX IF NOT EXISTS idx_error_log_created ON error_log (created_at DESC);
