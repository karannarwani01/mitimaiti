-- ============================================================================
-- 004_sync_user_settings_privileges_safety.sql
--
-- Backend code in auth.ts post-signup creates default rows in user_settings,
-- user_privileges, and user_safety using column names that don't match what
-- 001/002 created. Migration 002 partially addressed users but missed these
-- three tables. This migration adds the columns the code actually inserts to.
-- Additive only — does not touch or rename existing columns.
-- ============================================================================

-- ─── user_settings ─────────────────────────────────────────────────────────
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS discovery_enabled BOOLEAN DEFAULT true;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS show_online_status BOOLEAN DEFAULT true;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS show_distance BOOLEAN DEFAULT true;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS push_notifications BOOLEAN DEFAULT true;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS email_notifications BOOLEAN DEFAULT false;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS age_min INT DEFAULT 18;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS age_max INT DEFAULT 50;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS distance_km INT DEFAULT 100;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS gender_preference TEXT DEFAULT 'everyone';

-- ─── user_privileges ───────────────────────────────────────────────────────
ALTER TABLE user_privileges ADD COLUMN IF NOT EXISTS daily_likes INT DEFAULT 50;
ALTER TABLE user_privileges ADD COLUMN IF NOT EXISTS daily_super_likes INT DEFAULT 1;
ALTER TABLE user_privileges ADD COLUMN IF NOT EXISTS daily_rewinds INT DEFAULT 10;
ALTER TABLE user_privileges ADD COLUMN IF NOT EXISTS daily_comments INT DEFAULT 5;
ALTER TABLE user_privileges ADD COLUMN IF NOT EXISTS likes_used INT DEFAULT 0;
ALTER TABLE user_privileges ADD COLUMN IF NOT EXISTS super_likes_used INT DEFAULT 0;
ALTER TABLE user_privileges ADD COLUMN IF NOT EXISTS rewinds_used INT DEFAULT 0;
ALTER TABLE user_privileges ADD COLUMN IF NOT EXISTS comments_used INT DEFAULT 0;
ALTER TABLE user_privileges ADD COLUMN IF NOT EXISTS last_reset_at TIMESTAMPTZ DEFAULT now();

-- ─── user_safety ───────────────────────────────────────────────────────────
ALTER TABLE user_safety ADD COLUMN IF NOT EXISTS strikes INT DEFAULT 0;
ALTER TABLE user_safety ADD COLUMN IF NOT EXISTS last_reported_at TIMESTAMPTZ;

-- ─── Cleanup test user from earlier failed signup ──────────────────────────
-- The test phone +971505927520 was inserted into public.users but its
-- dependent rows failed silently. Delete it so the next /verify creates
-- a clean record with all tables populated.
DELETE FROM users WHERE phone = '+971505927520';
