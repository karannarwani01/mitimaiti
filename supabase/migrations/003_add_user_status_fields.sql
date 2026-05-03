-- ============================================================================
-- 003_add_user_status_fields.sql
--
-- Adds is_active and is_suspended status flags to users table.
-- These are referenced throughout the backend (socket.ts, actions.ts,
-- family.ts, safety.ts, auth.ts) but were never added in 001 or 002.
-- Without is_active, the auth.ts INSERT during /v1/auth/verify fails with
-- a "column does not exist" error and new users can't be provisioned.
-- ============================================================================

ALTER TABLE users ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_suspended BOOLEAN DEFAULT false;

-- Backfill any existing rows (in case they were created before this migration)
UPDATE users SET is_active = true WHERE is_active IS NULL;
UPDATE users SET is_suspended = false WHERE is_suspended IS NULL;
