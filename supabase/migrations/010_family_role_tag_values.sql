-- 010_family_role_tag_values.sql
--
-- BUG: family_access.role_tag had CHECK (role_tag IN
-- ('mom','dad','sibling','grandparent','uncle_aunt','other')) from 001, but
-- both clients send 'parent' / 'sibling' / 'friend'. So joining as Parent (the
-- default selection) or Friend violated the constraint and the join 500'd
-- (JOIN_FAILED) — the whole family/matchmaker feature was broken for 2 of 3
-- role options. Widen the constraint to the union of the intended granular
-- values AND the values the clients actually send (backward-compatible: old
-- rows with mom/dad/etc. stay valid).

ALTER TABLE family_access DROP CONSTRAINT IF EXISTS family_access_role_tag_check;

ALTER TABLE family_access ADD CONSTRAINT family_access_role_tag_check
  CHECK (role_tag IS NULL OR role_tag IN (
    'mom', 'dad', 'parent', 'sibling', 'grandparent',
    'uncle_aunt', 'relative', 'friend', 'other'
  ));
