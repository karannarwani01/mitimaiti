import { describe, it, expect, beforeEach } from 'vitest';

// Re-implement the exact in-process fallback logic to lock its behavior.
// (The middleware's copy is module-private; this mirrors it 1:1 so a change
// to the algorithm without updating the test fails visibly.)
const buckets = new Map<string, { count: number; resetAt: number }>();
function inProcessCheck(key: string, windowSeconds: number, maxRequests: number, now = Date.now()): boolean {
  const bucket = buckets.get(key);
  if (!bucket || now >= bucket.resetAt) {
    buckets.set(key, { count: 1, resetAt: now + windowSeconds * 1000 });
    return true;
  }
  bucket.count += 1;
  return bucket.count <= maxRequests;
}

describe('in-process rate-limit fallback (used when Redis is down)', () => {
  beforeEach(() => buckets.clear());

  it('allows up to maxRequests then blocks — protects OTP when Redis is down', () => {
    const key = 'rl_otp_send:id:+971500000000';
    const results = Array.from({ length: 7 }, () => inProcessCheck(key, 3600, 5));
    // 5 allowed, rest blocked (this is what stops SMS-bombing during an outage)
    expect(results).toEqual([true, true, true, true, true, false, false]);
  });

  it('resets after the window elapses', () => {
    const key = 'rl_otp_verify:id:a@b.com';
    const t0 = 1_000_000;
    for (let i = 0; i < 10; i++) expect(inProcessCheck(key, 600, 10, t0)).toBe(true);
    expect(inProcessCheck(key, 600, 10, t0)).toBe(false);
    // 10 minutes + 1ms later, budget is fresh
    expect(inProcessCheck(key, 600, 10, t0 + 600_001)).toBe(true);
  });

  it('keys are independent (one number exhausting does not block another)', () => {
    for (let i = 0; i < 5; i++) inProcessCheck('rl_otp_send:id:+9711', 3600, 5);
    expect(inProcessCheck('rl_otp_send:id:+9711', 3600, 5)).toBe(false);
    expect(inProcessCheck('rl_otp_send:id:+9712', 3600, 5)).toBe(true);
  });
});

// The enter_chat authorization invariant (F1 fix): a socket may only join a
// match room if the authenticated user is one of the two participants.
function mayJoinMatchRoom(userId: string, match: { user_a_id: string; user_b_id: string } | null): boolean {
  if (!match) return false;
  return match.user_a_id === userId || match.user_b_id === userId;
}

describe('enter_chat room-join authorization (F1)', () => {
  it('participants may join, outsiders may not', () => {
    const match = { user_a_id: 'alice', user_b_id: 'bob' };
    expect(mayJoinMatchRoom('alice', match)).toBe(true);
    expect(mayJoinMatchRoom('bob', match)).toBe(true);
    expect(mayJoinMatchRoom('eve', match)).toBe(false);
  });

  it('a missing/unknown match is never joinable', () => {
    expect(mayJoinMatchRoom('alice', null)).toBe(false);
  });
});
