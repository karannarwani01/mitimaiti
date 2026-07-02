-- 006_flat_discovery_filter_columns.sql
--
-- discovery.ts filters the feed by flat single-value columns on user_settings
-- (intent_filter, religion_filter, verified_only, …) but 001 only created the
-- legacy disc_* array columns, so every one of those filters silently no-oped.
-- Add the columns the backend actually reads so PATCH /me settings can persist
-- them and the feed query can apply them.

ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS verified_only BOOLEAN DEFAULT false;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS intent_filter TEXT;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS religion_filter TEXT;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS height_min INT;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS height_max INT;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS education_filter TEXT;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS smoking_filter TEXT;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS drinking_filter TEXT;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS fluency_filter TEXT;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS gotra_filter TEXT;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS dietary_filter TEXT;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS kundli_min INT DEFAULT 0;

-- Passport durable fallback writes a country alongside city/expiry
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS passport_country TEXT;

