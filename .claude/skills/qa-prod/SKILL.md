---
name: qa-prod
description: Run the end-to-end production QA runbook against the live MitiMaiti backend using the hidden test accounts — proves the full discover→comment-like→match→extend→chat→unmatch→daily-question loop with PASS/FAIL evidence.
---

# /qa-prod — Production API Runbook

Evidence-first QA against `https://mitimaiti-backend-tyxa.onrender.com/v1`
(the REAL backend — no mocks, per project rule). QA philosophy adapted
from gstack (MIT, Garry Tan); the runbook itself is MitiMaiti's own,
first proven 15/15 on 2026-07-03.

## Test accounts

Two hidden accounts exist: `cc-loop-test-a@mitimaiti.test` (man) and
`cc-loop-test-b@mitimaiti.test` (woman); password is in `backend/.env`
as `TEST_ACCOUNTS_PASSWORD` (gitignored — never hardcode it here).
- Tokens expire hourly — always re-`signInWithPassword` via supabase-js
  (service creds in `backend/.env`) at the start of a run.
- They are `is_hidden: true`. Unhide ONLY for the duration of the run,
  re-hide in cleanup — they must never linger in real users' feeds.

## The runbook (write as a node .mjs in backend/, run, then DELETE the file)

Each step asserts and prints `PASS/FAIL name — detail`:

1. `PATCH /me` both users (basics + intent + gender_preference)
   → assert rows in BOTH `users` and `basic_profiles` (dual-write).
2. Unhide both → `GET /feed` as A returns 200 and B's card is in the deck;
   `limits` carries likes/rewinds/comments budgets.
3. A `POST /action` like B WITH `comment` → 201, `comment_saved: true`,
   comment budget decremented.
4. B `GET /inbox` → A's card first, `like_comment` verbatim,
   `like_label == "Commented on your profile"`.
5. B likes A back → `is_match: true`, match row is `pending_first_message`
   with fresh 24h `expires_at` (REVIVED if a dissolved row existed —
   never dead).
6. `POST /chat/:id/extend` → 200 + `extendedOnce`; second call →
   400 `ALREADY_EXTENDED`; inbox match item carries `extended_once`.
7. First message → 201; sender's second message → 403
   `RESPECT_FIRST_LOCKED`; recipient reply → 201 unlocks; thread returns
   all messages in created_at order.
8. `POST /chat/:id/unmatch` → 200; match row shows
   `status=dissolved, is_dissolved, dissolved_at, dissolved_reason`.
9. `GET /action/prompt` → today's question; `POST` an answer →
   `answered_today: true` on re-fetch.
10. Photo lifecycle (optional, uses generated jpegs via sharp): upload ×2,
    `PATCH /me/media/:id/primary` (exactly ONE primary in DB), reorder,
    foreign-id reorder → 400 `INVALID_PHOTO_ID`, delete non-primary → 200,
    delete last → 400 `MIN_PHOTOS`.

## Cleanup (mandatory, even on failure)

- Re-hide both users, delete their `actions` rows and test `messages`.
- Leave the dissolved match row (unique pair row — revival reuses it).
- Delete the runbook script file.

## Reporting

Paste the raw PASS/FAIL table. Never summarize failures away — a FAIL is
a finding to fix in the same session (fix → redeploy → re-run), not a
caveat. Render deploys main automatically; wait for `/health` uptime to
reset (<90s) before re-running.
