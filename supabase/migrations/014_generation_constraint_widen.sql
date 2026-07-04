-- 014_generation_constraint_widen.sql
--
-- 4th CHECK-constraint-vs-code-value bug this run: sindhi_profiles.generation
-- from 001 only allows ('1st','2nd','3rd','4th+'), but BOTH clients' EditProfile
-- pickers save "1st Gen" / "2nd Gen" / "3rd Gen" / "4th Gen+". So a user setting
-- their generation had the write silently rejected — it never saved, which also
-- meant the (now-wired) generation discovery filter could never match anyone.
--
-- Widen the constraint to the union of both forms. The feed matches on the
-- leading digit, so mixing forms is fine. Drop by discovered name (inline CHECK
-- constraints from 001 are auto-named, but don't assume it).

DO $$
DECLARE c text;
BEGIN
  SELECT conname INTO c FROM pg_constraint
   WHERE conrelid = 'sindhi_profiles'::regclass
     AND contype = 'c'
     AND pg_get_constraintdef(oid) ILIKE '%generation%';
  IF c IS NOT NULL THEN
    EXECUTE 'ALTER TABLE sindhi_profiles DROP CONSTRAINT ' || quote_ident(c);
  END IF;
END $$;

ALTER TABLE sindhi_profiles ADD CONSTRAINT sindhi_profiles_generation_check
  CHECK (generation IN (
    '1st', '2nd', '3rd', '4th+',
    '1st Gen', '2nd Gen', '3rd Gen', '4th Gen+'
  ));
