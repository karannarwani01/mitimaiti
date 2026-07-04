-- 017_rose_super_like.sql
--
-- "Rose" = a priority like (Tinder Super Like / Hinge Rose). A Rose is a normal
-- like flagged is_rose=true: it surfaces at the TOP of the recipient's inbox and
-- is highlighted. Free-MVP: 1 Rose/day (tracked in Redis as its own currency,
-- separate from the 50 likes/day). This column is the only schema change.
--
-- First migration applied by the automated runner (backend/src/migrate.ts) —
-- runs on deploy before the server that reads the column.

ALTER TABLE actions ADD COLUMN IF NOT EXISTS is_rose BOOLEAN NOT NULL DEFAULT false;
