/**
 * Live E2E smoke test — exercises the critical path against a running backend
 * (prod by default) so regressions are caught automatically instead of by hand.
 *
 *   npm run e2e                       # against prod
 *   E2E_BASE_URL=http://localhost:4000 npm run e2e
 *
 * Needs SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, TEST_ACCOUNTS_PASSWORD in the
 * env (they're in backend/.env). Uses the service-role key only to mint
 * throwaway users + real sessions, then hits the public API over HTTP exactly
 * like real clients. Cleans everything up. Exit 0 = all passed, 1 = a failure.
 */
import { createClient } from '@supabase/supabase-js';

const BASE = process.env.E2E_BASE_URL || 'https://mitimaiti-backend-tyxa.onrender.com';
const { SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, TEST_ACCOUNTS_PASSWORD } = process.env;
if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !TEST_ACCOUNTS_PASSWORD) {
  console.error('E2E: missing env (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY / TEST_ACCOUNTS_PASSWORD)');
  process.exit(1);
}

const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const results = [];
function check(name, ok, detail = '') {
  results.push(ok);
  console.log(`  ${ok ? '✓ PASS' : '✗ FAIL'}  ${name}${detail ? ` — ${detail}` : ''}`);
}

async function mintUser() {
  const email = `e2e-${Date.now()}-${Math.random().toString(36).slice(2, 7)}@mitimaiti.test`;
  const { data: cr, error: ce } = await admin.auth.admin.createUser({
    email, password: TEST_ACCOUNTS_PASSWORD, email_confirm: true,
  });
  if (ce) throw new Error('createUser: ' + ce.message);
  const authId = cr.user.id;
  const { data: u, error: ue } = await admin.from('users').insert({
    auth_id: authId, display_name: 'E2E Smoke', is_active: true, is_banned: false,
    is_hidden: false, profile_completeness: 80, strikes: 0, deletion_requested: false,
    last_active: new Date().toISOString(),
  }).select('id').single();
  if (ue) throw new Error('users insert: ' + ue.message);
  await admin.from('basic_profiles').upsert({ user_id: u.id, gender: 'man', intent: 'marriage' });
  const { data: link, error: le } = await admin.auth.admin.generateLink({ type: 'magiclink', email });
  if (le) throw new Error('generateLink: ' + le.message);
  const otp = link?.properties?.email_otp;
  const { data: sess, error: se } = await admin.auth.verifyOtp({ email, token: otp, type: 'email' });
  if (se) throw new Error('verifyOtp: ' + se.message);
  const token = sess?.session?.access_token;
  if (!token) throw new Error('no access_token minted');
  return { authId, userId: u.id, token };
}

async function cleanup(users) {
  for (const u of users) {
    await admin.from('matches').delete().or(`user_a_id.eq.${u.userId},user_b_id.eq.${u.userId}`).then(() => {}, () => {});
    await admin.from('actions').delete().or(`actor_id.eq.${u.userId},target_id.eq.${u.userId}`).then(() => {}, () => {});
    await admin.from('basic_profiles').delete().eq('user_id', u.userId).then(() => {}, () => {});
    await admin.from('users').delete().eq('id', u.userId).then(() => {}, () => {});
    await admin.auth.admin.deleteUser(u.authId).then(() => {}, () => {});
  }
}

async function api(path, token, method = 'GET', body) {
  const res = await fetch(BASE + path, {
    method,
    headers: {
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  let out = null;
  try { out = await res.json(); } catch { /* non-JSON */ }
  return { status: res.status, body: out };
}

async function main() {
  console.log(`\n=== MitiMaiti E2E smoke → ${BASE} ===\n`);

  const h = await api('/health');
  check('health: 200 + db + redis ok',
    h.status === 200 && h.body?.status === 'ok' && h.body?.db?.status === 'ok' && h.body?.redis?.status === 'ok',
    `status=${h.body?.status} db=${h.body?.db?.status} redis=${h.body?.redis?.status}`);

  const noauth = await api('/v1/me');
  check('auth enforced: no token → 401', noauth.status === 401, `status=${noauth.status}`);

  const users = [];
  try {
    const A = await mintUser(); users.push(A);
    check('auth: minted a real session for a throwaway user', !!A.token, `A=${A.userId.slice(0, 8)}`);

    check('GET /v1/me (profile loads)', (await api('/v1/me', A.token)).status === 200);
    check('GET /v1/feed (discovery query runs)', (await api('/v1/feed', A.token)).status === 200);
    check('GET /v1/inbox (likes inbox)', (await api('/v1/inbox', A.token)).status === 200);

    // ── the core dating loop: like → mutual like → match → open chat ──
    const B = await mintUser(); users.push(B);
    const likeAB = await api('/v1/action', A.token, 'POST', { target_user_id: B.userId, type: 'like' });
    check('A likes B → 201, not a match yet',
      likeAB.status === 201 && likeAB.body?.data?.is_match === false,
      `status=${likeAB.status} is_match=${likeAB.body?.data?.is_match}`);

    const likeBA = await api('/v1/action', B.token, 'POST', { target_user_id: A.userId, type: 'like' });
    const matchId = likeBA.body?.data?.match_id;
    check('B likes A back → MATCH created',
      likeBA.status === 201 && likeBA.body?.data?.is_match === true && !!matchId,
      `is_match=${likeBA.body?.data?.is_match} match_id=${matchId ? String(matchId).slice(0, 8) : 'null'}`);

    const chat = await api(`/v1/chat/${matchId || 'none'}`, A.token);
    check('A can open the matched chat', !!matchId && chat.status === 200, `status=${chat.status}`);
  } catch (e) {
    check('critical path', false, e.message);
  } finally {
    await cleanup(users);
    console.log(`  · cleaned up ${users.length} throwaway user(s)`);
  }

  const passed = results.filter(Boolean).length;
  console.log(`\n=== ${passed}/${results.length} passed, ${results.length - passed} failed ===\n`);
  process.exit(results.every(Boolean) ? 0 : 1);
}

main().catch((e) => { console.error('E2E CRASHED:', e.message); process.exit(1); });
