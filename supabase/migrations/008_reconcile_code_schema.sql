-- 008_reconcile_code_schema.sql
--
-- CODE-vs-SCHEMA RECONCILIATION (2026-07-03).
-- The live database contains exactly what migrations 001–006 define, but the
-- backend reads/writes a number of columns that only ever existed as ad-hoc
-- SQL on an earlier database and were never captured in a migration. Until
-- this file is applied, in production: the feed always returns
-- PROFILE_INCOMPLETE (basic_profiles is missing every identity column),
-- match creation fails (matches.cultural_score), unmatch/block-dissolve 500
-- (matches.dissolved_at), and appeals/deletion-feedback/prompt-rotation hit
-- missing tables.
--
-- Derived by diffing every table.column referenced in backend/src against the
-- live schema (PostgREST probes). Fully idempotent — safe to re-run.

-- ── basic_profiles: identity columns the feed/inbox/admin read ──────────────
ALTER TABLE basic_profiles ADD COLUMN IF NOT EXISTS display_name TEXT;
ALTER TABLE basic_profiles ADD COLUMN IF NOT EXISTS date_of_birth DATE;
ALTER TABLE basic_profiles ADD COLUMN IF NOT EXISTS gender TEXT;
ALTER TABLE basic_profiles ADD COLUMN IF NOT EXISTS city TEXT;
ALTER TABLE basic_profiles ADD COLUMN IF NOT EXISTS state TEXT;
ALTER TABLE basic_profiles ADD COLUMN IF NOT EXISTS country TEXT;
ALTER TABLE basic_profiles ADD COLUMN IF NOT EXISTS intent TEXT;
ALTER TABLE basic_profiles ADD COLUMN IF NOT EXISTS bio TEXT;

-- ── matches ──────────────────────────────────────────────────────────────────
ALTER TABLE matches ADD COLUMN IF NOT EXISTS cultural_score INT DEFAULT 0;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS dissolved_at TIMESTAMPTZ;

-- ── messages: code orders by created_at and tracks read/media state ──────────
ALTER TABLE messages ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();
ALTER TABLE messages ADD COLUMN IF NOT EXISTS is_read BOOLEAN DEFAULT false;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS media_type TEXT;

-- ── users ────────────────────────────────────────────────────────────────────
ALTER TABLE users ADD COLUMN IF NOT EXISTS ban_expires TIMESTAMPTZ;

-- ── user_privileges: passport fallback cleared by cron ──────────────────────
ALTER TABLE user_privileges ADD COLUMN IF NOT EXISTS passport_city TEXT;
ALTER TABLE user_privileges ADD COLUMN IF NOT EXISTS passport_expires TIMESTAMPTZ;

-- ── family_access ────────────────────────────────────────────────────────────
ALTER TABLE family_access ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'pending';
ALTER TABLE family_access ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;
ALTER TABLE family_access ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ;

-- ── family_suggestions ───────────────────────────────────────────────────────
ALTER TABLE family_suggestions ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'pending';
ALTER TABLE family_suggestions ADD COLUMN IF NOT EXISTS suggested_by UUID;

-- ── notif_log ────────────────────────────────────────────────────────────────
ALTER TABLE notif_log ADD COLUMN IF NOT EXISTS title TEXT;
ALTER TABLE notif_log ADD COLUMN IF NOT EXISTS body TEXT;
ALTER TABLE notif_log ADD COLUMN IF NOT EXISTS fcm_message_id TEXT;

-- ── reports: moderation flow ─────────────────────────────────────────────────
ALTER TABLE reports ADD COLUMN IF NOT EXISTS moderator_id UUID;
ALTER TABLE reports ADD COLUMN IF NOT EXISTS resolution_note TEXT;

-- ── strikes: moderation flow ─────────────────────────────────────────────────
ALTER TABLE strikes ADD COLUMN IF NOT EXISTS action TEXT;
ALTER TABLE strikes ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'active';
ALTER TABLE strikes ADD COLUMN IF NOT EXISTS severity TEXT;
ALTER TABLE strikes ADD COLUMN IF NOT EXISTS moderator_id UUID;
ALTER TABLE strikes ADD COLUMN IF NOT EXISTS report_id UUID;

-- ── daily_prompts: columns the midnight rotation cron uses ──────────────────
ALTER TABLE daily_prompts ADD COLUMN IF NOT EXISTS date DATE;
ALTER TABLE daily_prompts ADD COLUMN IF NOT EXISTS category TEXT;
ALTER TABLE daily_prompts ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT false;
CREATE INDEX IF NOT EXISTS idx_daily_prompts_date ON daily_prompts (date);

-- ── Missing tables ───────────────────────────────────────────────────────────

-- Strike appeals (safety.ts submits, admin.ts reviews)
CREATE TABLE IF NOT EXISTS appeals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  strike_id UUID,
  text TEXT,
  status TEXT DEFAULT 'pending',
  reviewed_at TIMESTAMPTZ,
  reviewed_by UUID,
  reviewer_note TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Exit feedback captured at account deletion (must SURVIVE the user's hard
-- delete — intentionally no FK cascade)
CREATE TABLE IF NOT EXISTS deletion_feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID,
  reason TEXT,
  scheduled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Rotation pool the midnight cron draws tomorrow's daily prompt from
CREATE TABLE IF NOT EXISTS prompt_pool (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  question TEXT NOT NULL,
  category TEXT DEFAULT 'general',
  sort_order INT,
  used BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Referenced by the account hard-delete cleanup
CREATE TABLE IF NOT EXISTS prompt_answers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  prompt_id UUID,
  answer TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Seed the rotation pool once from the questions already in daily_prompts
INSERT INTO prompt_pool (question, category, sort_order)
SELECT dp.question, COALESCE(dp.category, 'general'),
       ROW_NUMBER() OVER (ORDER BY dp.created_at)
FROM daily_prompts dp
WHERE dp.question IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM prompt_pool);

-- ── RLS (backend uses the service key which bypasses RLS; enabling it keeps
--    the anon key locked out, consistent with the other tables) ──────────────
ALTER TABLE appeals ENABLE ROW LEVEL SECURITY;
ALTER TABLE deletion_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE prompt_pool ENABLE ROW LEVEL SECURITY;
ALTER TABLE prompt_answers ENABLE ROW LEVEL SECURITY;
