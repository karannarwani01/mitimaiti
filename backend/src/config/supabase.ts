import { createClient, SupabaseClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL) {
  throw new Error('Missing SUPABASE_URL environment variable');
}

if (!SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error('Missing SUPABASE_SERVICE_ROLE_KEY environment variable');
}

// Privileged client for all DB/storage operations. Its Authorization header
// must stay pinned to the service_role key, so NEVER call .auth.signIn*/
// verifyOtp/refreshSession on this instance — doing so mutates the singleton's
// in-memory session and downgrades subsequent storage/DB calls to the signed-in
// user's role, causing "new row violates row-level security policy".
export const supabase: SupabaseClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

// Dedicated client for user auth operations (signInWithIdToken, verifyOtp,
// signInWithOtp, refreshSession). Kept separate so that minting a user session
// never contaminates the privileged `supabase` client above. This instance is
// only ever used for auth and never touches RLS-protected tables/buckets.
export const supabaseAuth: SupabaseClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

export default supabase;
