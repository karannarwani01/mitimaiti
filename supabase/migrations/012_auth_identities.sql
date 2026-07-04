-- 012_auth_identities.sql
--
-- Guarantees a linked Google (or other) login lands on the ORIGINAL profile,
-- without depending on Supabase/GoTrue's automatic same-email linking.
--
-- A profile is keyed off users.auth_id (one Supabase auth user). When a user
-- links Google to a phone profile we set the Google email on the phone auth
-- user, and rely on GoTrue to route a later Google sign-in back to it. If
-- GoTrue instead hands back a DIFFERENT auth user, /google/verify resolves the
-- profile by its verified email and records that auth_id here as an ALIAS.
-- The auth middleware then maps the alias → the same profile on every request.
--
-- users.auth_id remains the primary identity; this table holds secondary ones.

CREATE TABLE IF NOT EXISTS auth_identities (
  auth_id    TEXT PRIMARY KEY,
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider   TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_auth_identities_user ON auth_identities (user_id);
