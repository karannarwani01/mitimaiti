-- 011_reports_status_values.sql
--
-- BUG (same class as 010): reports.status had CHECK IN
-- ('pending','reviewing','resolved') from 001, but the admin moderation
-- handler writes 'actioned' (warn/suspend/ban) and 'dismissed' (dismiss).
-- Those updates have no error check, so they silently no-op — every
-- moderation action left the report stuck at 'pending', so handled reports
-- never cleared from the queue and moderators re-reviewed them forever.
-- Widen the constraint to the union of the intended values and what the
-- code actually writes.

ALTER TABLE reports DROP CONSTRAINT IF EXISTS reports_status_check;

ALTER TABLE reports ADD CONSTRAINT reports_status_check
  CHECK (status IN (
    'pending', 'reviewing', 'reviewed', 'resolved', 'actioned', 'dismissed'
  ));
