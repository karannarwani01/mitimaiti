/**
 * Live E2E smoke test — exercises the critical path against a running backend
 * (prod by default) so regressions are caught automatically instead of by hand.
 *
 *   npm run e2e                       # against prod
 *   E2E_BASE_URL=http://localhost:4000 npm run e2e
 *
 * Needs SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, TEST_ACCOUNTS_PASSWORD in the
 * env (they're in backend/.env). Uses the service-role key only to mint a
 * throwaway user + a real session, then hits the public API as that user over
 * HTTP exactly like a real client. Cleans the user up afterwards. Exit code 0 =
 * all passed, 1 = something failed (so it can gate CI / the loop).
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
    is_hidden: false, profile_completeness: 60, strikes: 0, deletion_requested: false,
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

async function cleanup(u) {
  if (!u) return;
  await admin.from('basic_profiles').delete().eq('user_id', u.userId).then(() => {}, () => {});
  await admin.from('users').delete().eq('id', u.userId).then(() => {}, () => {});
  await admin.auth.admin.deleteUser(u.authId).then(() => {}, () => {});
}

async function api(path, token) {
  const res = await fetch(BASE + path, { headers: token ? { Authorization: `Bearer ${token}` } : {} });
  let body = null;
  try { body = await res.json(); } catch { /* non-JSON */ }
  return { status: res.status, body };
}

async function main() {
  console.log(`\n=== MitiMaiti E2E smoke → ${BASE} ===\n`);

  const h = await api('/health');
  check('health: 200 + db + redis ok',
    h.status === 200 && h.body?.status === 'ok' && h.body?.db?.status === 'ok' && h.body?.redis?.status === 'ok',
    `status=${h.body?.status} db=${h.body?.db?.status} redis=${h.body?.redis?.status}`);

  const noauth = await api('/v1/me');
  check('auth enforced: no token → 401', noauth.status === 401, `status=${noauth.status}`);

  let u;
  try {
    u = await mintUser();
    check('auth: minted a real session for a throwaway user', !!u.token, `user=${u.userId.slice(0, 8)}`);

    const me = await api('/v1/me', u.token);
    check('GET /v1/me (profile loads)', me.status === 200, `status=${me.status}`);

    const feed = await api('/v1/feed', u.token);
    check('GET /v1/feed (discovery query runs)', feed.status === 200, `status=${feed.status}`);

    const inbox = await api('/v1/inbox', u.token);
    check('GET /v1/inbox (likes inbox)', inbox.status === 200, `status=${inbox.status}`);
  } catch (e) {
    check('critical path', false, e.message);
  } finally {
    await cleanup(u);
    console.log('  · cleaned up throwaway user');
  }

  const passed = results.filter(Boolean).length;
  console.log(`\n=== ${passed}/${results.length} passed, ${results.length - passed} failed ===\n`);
  process.exit(results.every(Boolean) ? 0 : 1);
}

main().catch((e) => { console.error('E2E CRASHED:', e.message); process.exit(1); });
