-- 009_backfill_basic_profiles_identity.sql
--
-- PATCH /me wrote identity fields (display_name, dob, gender, city, ...)
-- only to the users table, while discovery/inbox/admin read them from
-- basic_profiles — so basic_profiles stayed empty and the feed returned
-- PROFILE_INCOMPLETE even for completed profiles. The backend now
-- dual-writes; this backfills basic_profiles for accounts created before
-- the fix. Idempotent.

INSERT INTO basic_profiles (user_id, display_name, date_of_birth, gender, city, state, country, intent, bio)
SELECT u.id, u.display_name, u.dob, u.gender, u.city, u.state, u.country, u.intent, u.bio
FROM users u
WHERE u.display_name IS NOT NULL OR u.dob IS NOT NULL OR u.city IS NOT NULL
ON CONFLICT (user_id) DO UPDATE SET
  display_name  = COALESCE(EXCLUDED.display_name,  basic_profiles.display_name),
  date_of_birth = COALESCE(EXCLUDED.date_of_birth, basic_profiles.date_of_birth),
  gender        = COALESCE(EXCLUDED.gender,        basic_profiles.gender),
  city          = COALESCE(EXCLUDED.city,          basic_profiles.city),
  state         = COALESCE(EXCLUDED.state,         basic_profiles.state),
  country       = COALESCE(EXCLUDED.country,       basic_profiles.country),
  intent        = COALESCE(EXCLUDED.intent,        basic_profiles.intent),
  bio           = COALESCE(EXCLUDED.bio,           basic_profiles.bio);
