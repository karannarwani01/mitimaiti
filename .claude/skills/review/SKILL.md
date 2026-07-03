---
name: review
description: Pre-landing review of the current diff against origin/main — two-pass checklist tuned to MitiMaiti's stack (Express+Supabase backend, Kotlin Compose Android, SwiftUI iOS). Run before any push to main.
---

# /review — MitiMaiti Pre-Landing Review

Review `git diff origin/main` (or the stated range). Be specific — cite
`file:line`, suggest fixes. Only flag real problems. Methodology adapted
from gstack (MIT, Garry Tan) and tuned to this repo.

**Fix-first protocol:** apply obvious mechanical fixes yourself, then batch
genuinely ambiguous judgment calls into ONE question. Output format:

```
Pre-Landing Review: N issues (X critical, Y informational)
AUTO-FIXED:
- [file:line] problem → fix applied
NEEDS INPUT:
- [file:line] problem — recommended fix
```

## Pass 1 — CRITICAL

### Cross-layer contract sync (the #1 bug class in this repo)
- Every new/changed API field: verify the exact JSON key on all THREE
  layers. Backend responses are snake_case (except `/chat/:id/extend`,
  which is camelCase); request bodies are snake_case everywhere
  (zod `.strict()` — unknown keys 400).
- iOS decodes via `convertFromSnakeCase` + `APIEnvelope` whose `error` is
  an OBJECT `{code,message}` — never match on prose alone; match `code`.
- Android parses `Map<String,Any>` by hand — a typo'd key silently yields
  null, not an error. Read the parse site.
- New error codes (429/400 variants) need typed cases in BOTH clients
  (Android `APIError` sealed class, iOS `APIError` enum + HTTPClient).

### Database schema truth
- Prod == `supabase/migrations/*.sql` EXACTLY. Any column/table the code
  touches must exist in a migration file. If the diff adds a column
  reference, it must add a migration (idempotent `IF NOT EXISTS`) AND the
  code must degrade gracefully until it's applied (see
  `commentColumnKnownMissing` in actions.ts for the pattern).
- Profile identity fields are DUAL-WRITTEN to `users` AND `basic_profiles`
  (PATCH /me). Feed/inbox/admin read `basic_profiles`; /me reads `users`.
  Never write to only one.
- Column names in `.select()/.eq()/.order()` — verify against migrations;
  PostgREST returns an error object that supabase-js does NOT throw, so a
  wrong name silently no-ops (`{ data: null }`). Check every destructure.
- `matches` is unique per pair — re-match must revive, never insert.
- ADD COLUMN with DEFAULT on a populated table: backfill legacy columns.

### Races & atomicity
- check-then-insert without a unique constraint (or 23505 catch + reselect
  — see match creation in actions.ts).
- Two-statement state flips: order them fail-safe (e.g. set-primary
  promotes FIRST, demotes second — never leave zero primaries).
- Daily counters: Redis is the cache, `actions` table is the truth —
  a new counter needs increment + refund-on-rewind + DB fallback count.

### Enum/value completeness
- New enum value / status string / action kind: READ every consumer
  (switch/when/filter arrays) on all three platforms, not just grep.
  Include zod schemas, Kotlin `when`, Swift `switch` with `default`.

## Pass 2 — INFORMATIONAL

- **iOS/Android parity:** any user-facing change must land on BOTH apps in
  the same commit (hard rule). Compare feature surface, copy, and limits.
- **Fake content ban:** no invented labels/claims in UI ("liked your
  vibe"-style randomization) — server-backed values only.
- **Copy rules:** never the word "diaspora" in user-facing copy.
- **Time windows:** `todayKey()` is UTC — flag date-key logic that assumes
  local midnight; countdown math must use server-authoritative expiries.
- **Optimistic UI:** local mutations before the server confirms need a
  restore path on failure (see comment-limit card restore in
  FeedViewModel). Server-first for destructive ops (photo delete).
- **Socket events:** iOS subscribes via multicast PassthroughSubjects —
  never add a single-consumer AsyncStream; Android SocketManager mirrors
  event names with backend `emitToUser` (grep both sides).
- **Dead writes:** columns nothing reads (unread_a/b class of bug).
- **N+1:** per-row awaits inside inbox/feed loops — batch with `.in()`.

## Verification gates (all must pass before push)

```
cd backend && npm run typecheck && npm test
cd android && ./gradlew.bat :app:compileDebugKotlin
# iOS compiles on CI (macOS job) — after push: gh run watch <id> --exit-status
```

Push to main only when green; Render auto-deploys backend from main.
