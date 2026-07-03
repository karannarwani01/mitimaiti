---
name: security-audit
description: Security audit of the MitiMaiti stack — secrets archaeology, OWASP Top 10 pass over the Express API, STRIDE per component, and dating-app data classification. Run before widening the user base or after any auth/media/payment change.
---

# /security-audit — MitiMaiti Security Audit

Audit phases adapted from gstack's CSO skill (MIT, Garry Tan), cut down to
what matters for this stack. Report findings as
`SEVERITY [component] finding — file:line — fix`, CRITICAL first. Apply
mechanical fixes immediately; batch judgment calls into one question.

## Phase 1 — Secrets archaeology (public repo — highest priority)

The repo is PUBLIC (karannarwani01/mitimaiti) and has leaked a Twilio
Auth Token in the past. Every audit re-runs:

```bash
git ls-files '*.env' '.env.*' | grep -v 'example\|sample\|template'   # must be empty
git log -p --all -G "SUPABASE_SERVICE_ROLE_KEY=|TWILIO|sk-|AKIA|ghp_|xoxb-|-----BEGIN" -- "*.env" "*.yml" "*.json" "*.md" 2>/dev/null | head -50
grep -rn "eyJhbGciOi\|sk_live_\|AKIA\|ghp_" --include="*.ts" --include="*.kt" --include="*.swift" backend/src android/app/src ios/MitiMaiti admin/src
```

Also check: `google-services.json` stays gitignored; no service-role key
in client code (clients must only ever hold user JWTs); CI workflows use
`${{ secrets.* }}` — no inline values. Severity: CRITICAL for any live
credential in history (rotation required even if later removed — it was
exposed). FP rules: placeholders (`your_`, `changeme`, `***`) excluded;
the anon public key is fine, the service key never is.

## Phase 2 — OWASP pass over the API (backend/src/routes)

- **A01 Access control (IDOR):** every route taking a matchId/userId/photo
  id must scope by the authed user (`verifyMatchAccess`, `.eq('user_id',
  user.id)` on media ops). Grep new routes for params used in queries
  without an ownership filter. Admin routes must chain `requireAdmin`.
- **A03 Injection:** PostgREST `.or(...)` strings interpolate raw ids —
  UUIDs from zod-validated params only, never free text. Flag any
  `.or()`/`.filter()` built from unvalidated input.
- **A04 Design:** rate limits present on OTP send/verify (per identity),
  action/chat endpoints; daily budgets server-authoritative.
- **A05 Misconfig:** CORS_ORIGINS not `*` in prod; error handler must not
  leak stack traces; Express `x-powered-by` disabled.
- **A07 Auth:** Supabase JWTs verified via `auth.getUser` (not local
  decode); revocation blacklist in Redis; socket handshake auths the
  token, not just presence.
- **A09 Logging:** auth failures, admin actions, moderation decisions all
  logged; logs free of message content and tokens.
- **A10 SSRF:** any URL fetched server-side must be constant or
  allowlisted (media URLs come from our own storage bucket only).

## Phase 3 — STRIDE, per component

Run the six questions (Spoofing / Tampering / Repudiation / Info
disclosure / DoS / Privilege elevation) against each of: auth+OTP flow,
socket chat, media upload pipeline, discovery/feed, moderation+admin
panel, FCM push pipeline, cron jobs. One line per cell; flag only gaps.

## Phase 4 — Data classification (dating app = high sensitivity)

```
RESTRICTED (breach = legal/regulatory + community harm):
  religion, gotra, community sub-group, kundli data  ← special-category
  chat messages, voice notes, photos, selfie-verification flow
  phone numbers, emails, DOB, location
CONFIDENTIAL: service keys, FCM tokens, moderation records, block lists
INTERNAL: logs, analytics counters
```

For each RESTRICTED item verify: where stored, who can query it (RLS is
NOT protection — the backend uses the service key; access control lives
in route code), retention on account deletion (cron hard-delete covers
it?), and exposure in API responses (does the feed leak fields the card
doesn't need?).

## Output

```
Security Audit: N findings (C critical / H high / M medium)
CRITICAL: ...
FIXED NOW: ...
NEEDS DECISION: ...
Rotation list: [any credential ever exposed]
```
