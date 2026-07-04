-- 013_generation_family_filters.sql
--
-- Both clients expose "Generation" and "Family Plans" discovery filters (and
-- count them as active filters), but 006 never added their user_settings
-- columns — so they could not be saved or applied, and selecting them did
-- nothing. Add the columns so the feed can honour them (discovery.ts matches
-- generation against sindhi_profiles.generation and family_plans against
-- basic_profiles.want_kids).

ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS generation_filter TEXT;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS family_plans_filter TEXT;
