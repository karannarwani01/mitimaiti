import { createClient } from '@supabase/supabase-js';
import { readFileSync } from 'fs';
const admin = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth:{persistSession:false}});
const PW = process.env.TEST_ACCOUNTS_PASSWORD;
const noface = readFileSync('C:/Users/user/AppData/Local/Temp/claude/C--Users-user/0aef1173-a1c9-4002-8809-11068137dea3/scratchpad/noface.jpg');
async function probe() {
  const email = `cc-poll-${Date.now()}@mitimaiti.test`;
  const { data: cr } = await admin.auth.admin.createUser({ email, password: PW, email_confirm: true });
  const authId = cr.user.id;
  const { data: u } = await admin.from('users').insert({ auth_id: authId, email, display_name:'Poll', is_verified:false, is_active:true, is_banned:false, is_hidden:true, profile_completeness:40, strikes:0, deletion_requested:false, last_active:new Date().toISOString() }).select('id').single();
  const c = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth:{persistSession:false}});
  const { data: s } = await c.auth.signInWithPassword({ email, password: PW });
  const boundary='Z'+Math.random().toString(36);
  const body=Buffer.concat([Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="selfie"; filename="s.jpg"\r\nContent-Type: image/jpeg\r\n\r\n`),noface,Buffer.from(`\r\n--${boundary}--\r\n`)]);
  const r=await fetch('https://mitimaiti-backend-tyxa.onrender.com/v1/me/verify',{method:'POST',headers:{Authorization:`Bearer ${s.session.access_token}`,'Content-Type':`multipart/form-data; boundary=${boundary}`},body});
  const j=await r.json().catch(()=>null);
  await admin.from('users').delete().eq('id', u.id); await admin.auth.admin.deleteUser(authId);
  return j?.error?.code;
}
for (let i=1;i<=15;i++){
  const code = await probe();
  if (code !== 'VERIFICATION_UNAVAILABLE') { console.log(`CREDS LIVE after ${i*2}min (probe code=${code})`); process.exit(0); }
  await new Promise(r=>setTimeout(r,120000));
}
console.log('TIMEOUT: creds still not detected after 30min');
process.exit(3);
