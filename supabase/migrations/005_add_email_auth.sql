-- ============================================================================
-- 005_add_email_auth.sql
--
-- Enables email-based sign-up alongside the existing phone OTP flow.
-- Adds users.email and relaxes the NOT NULL constraint on users.phone so
-- email-only users can be provisioned without a phone number.
--
-- Auth itself remains delegated to Supabase Auth (supabase.auth.signInWithOtp
-- with {email}); this migration only widens our application-side users table.
-- ============================================================================

ALTER TABLE users ADD COLUMN IF NOT EXISTS email TEXT;
ALTER TABLE users ADD CONSTRAINT users_email_unique UNIQUE (email);
ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;

CREATE INDEX IF NOT EXISTS idx_users_email ON users (email)
  WHERE email IS NOT NULL;
