-- 007_like_comments.sql
--
-- Hinge-style "Like with a Comment": a like may carry a short note that the
-- recipient sees on their Liked You card ("Commented on your profile").
-- The backend already degrades gracefully while this column is missing
-- (the like is recorded, the comment is dropped and the client is told via
-- comment_saved: false), so applying this migration simply switches the
-- feature on.

ALTER TABLE actions ADD COLUMN IF NOT EXISTS comment TEXT
  CHECK (char_length(comment) <= 280);

-- Commented likes float to the top of Liked You; partial index keeps that
-- sort cheap without bloating the main received-likes index.
CREATE INDEX IF NOT EXISTS idx_actions_commented_likes
  ON actions (target_id, created_at DESC)
  WHERE kind = 'like' AND comment IS NOT NULL;
