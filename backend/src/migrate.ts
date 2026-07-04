/**
 * Automated migration runner.
 *
 * Applies any un-applied files in supabase/migrations/ to the database, tracked
 * in a `schema_migrations` table so each file runs exactly once. Runs on boot
 * (before the server) so schema changes ship with a deploy — no more manual
 * SQL-editor steps.
 *
 * Mechanism: uses the existing Supabase service-role key (already in the env) —
 * NO database password, NO new secret. DDL runs via the `exec_migration_sql`
 * function (SECURITY DEFINER, granted only to service_role); the applied-set is
 * tracked in the `schema_migrations` table. Both are created once by the
 * bootstrap SQL in supabase/migrations/016_migration_runner.sql.
 *
 * Safety:
 *  - No-op if the Supabase env is unset (won't break local/CI boots).
 *  - Each migration file runs in a single PostgREST call (atomic per file).
 *  - A failure aborts the boot loudly rather than starting on a half-migrated
 *    schema.
 *  - `--baseline` marks existing files as applied WITHOUT running them, for the
 *    one-time switchover from manually-applied migrations.
 *
 * Usage:
 *   node dist/migrate.js            # apply pending migrations
 *   node dist/migrate.js --baseline # mark all current files as already applied
 */
import { readdirSync, readFileSync, existsSync } from 'fs';
import { resolve } from 'path';
import { createClient } from '@supabase/supabase-js';

function findMigrationsDir(): string {
  const candidates = [
    resolve(__dirname, '../../supabase/migrations'), // dist/ -> backend -> repo/supabase
    resolve(process.cwd(), 'supabase/migrations'), // cwd = repo root
    resolve(process.cwd(), '../supabase/migrations'), // cwd = backend
    resolve(__dirname, '../supabase/migrations'),
  ];
  for (const c of candidates) if (existsSync(c)) return c;
  throw new Error('migrations dir not found; tried:\n  ' + candidates.join('\n  '));
}

async function main(): Promise<void> {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    console.log('[migrate] Supabase env not set — skipping migrations');
    return;
  }
  const baseline = process.argv.includes('--baseline');
  const admin = createClient(url, key, { auth: { persistSession: false } });

  const dir = findMigrationsDir();
  const files = readdirSync(dir)
    .filter((f) => f.endsWith('.sql'))
    .sort();

  const { data: appliedRows, error: selErr } = await admin
    .from('schema_migrations')
    .select('filename');
  if (selErr) {
    throw new Error(
      `cannot read schema_migrations — run the 016 bootstrap first (${selErr.message})`
    );
  }
  const applied = new Set((appliedRows || []).map((r) => r.filename as string));
  const pending = files.filter((f) => !applied.has(f));

  if (baseline) {
    if (pending.length) {
      const { error } = await admin
        .from('schema_migrations')
        .insert(pending.map((filename) => ({ filename })));
      if (error) throw new Error(`baseline insert failed: ${error.message}`);
    }
    console.log(`[migrate] baseline: marked ${pending.length} file(s) applied (not run)`);
    return;
  }

  if (!pending.length) {
    console.log(`[migrate] up to date — ${applied.size} applied, 0 pending`);
    return;
  }

  for (const f of pending) {
    const sql = readFileSync(resolve(dir, f), 'utf8');
    console.log(`[migrate] applying ${f} ...`);
    const { error: execErr } = await admin.rpc('exec_migration_sql', { sql });
    if (execErr) throw new Error(`migration ${f} failed: ${execErr.message}`);
    const { error: insErr } = await admin.from('schema_migrations').insert({ filename: f });
    if (insErr) throw new Error(`migration ${f} applied but not recorded: ${insErr.message}`);
    console.log(`[migrate] ✓ applied ${f}`);
  }
  console.log(`[migrate] done — applied ${pending.length} new migration(s)`);
}

main().catch((e) => {
  console.error('[migrate] FAILED:', e instanceof Error ? e.message : e);
  process.exit(1);
});
