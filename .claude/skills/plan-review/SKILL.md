---
name: plan-review
description: Challenge a feature plan before building it — scope cut, edge cases, failure modes, rollout, plus an independent fresh-context second opinion. Use when a feature is more than a one-file change.
---

# /plan-review — Feature Plan Challenge

Review framework distilled from gstack's plan-ceo-review (MIT, Garry
Tan), compacted for a two-person team shipping to a 100-customer test.
Review the plan (stated in chat or a file) section by section; a section
with no findings gets one line: "No issues."

## Sections

1. **What already exists** — search the repo FIRST. List existing code
   that partially solves this (backend columns, dead endpoints, half-built
   client plumbing). MitiMaiti has repeatedly had backend-ready features
   with no UI (extend-match, daily question, comment quotas) — reuse
   beats rebuild.
2. **Scope cut** — what's the smallest version that tests the hypothesis
   with 100 users? Produce an explicit **NOT in scope** list with one-line
   rationales. Monetization-style tiers are out by product rule (everyone
   equal).
3. **Three-platform cost** — every user-facing element ships on Android
   AND iOS in the same commit, and iOS is compile-checked only via CI
   from this PC. Price that in; a backend-only phase 1 is often the
   right cut.
4. **Schema impact** — any new column/table needs a migration file AND a
   graceful-degradation path until it's applied (prod == migration files,
   no exceptions). Backfills for populated tables.
5. **Error & failure map** — for each new codepath:
   `CODEPATH | FAILURE | HANDLED? | USER SEES? | LOGGED?`
   Include the boring ones: Redis down, PostgREST error objects (which
   do NOT throw), socket disconnected, token expired mid-flow.
6. **Edge cases & abuse** — blocked users, dissolved matches, hidden/
   banned accounts, daily-limit exhaustion, double-taps, resumed
   onboarding, re-match after unmatch (revival!), timezone/date keys.
7. **Test & evidence plan** — what proves it works: vitest units for pure
   logic, /qa-prod runbook step for the live flow, which CI jobs gate it.
   Name the evidence before writing code.
8. **Rollout** — Render auto-deploys main on push: is the backend change
   safe to deploy BEFORE clients update (old clients hitting new API,
   new clients hitting old API during deploy)? Additive-only responses;
   optional request fields.
9. **Long-term trajectory** — one paragraph: does this move toward the
   community-matchmaking vision or is it a rut-risk detour?

## Outside voice (always)

After the sections, spawn ONE fresh-context subagent (general-purpose)
with the plan text and no prior conversation, prompted to find the three
strongest objections and one cheaper alternative. Integrate or rebut its
points explicitly — don't silently drop them.

## Decision protocol

One issue = one decision. Present 2–3 options each (including "do
nothing" where sane) with one-line effort/risk. Zero findings in a
section → move on without ceremony. End with the NOT-in-scope list, the
failure-mode table, and the evidence plan — those three artifacts are
the deliverable.
