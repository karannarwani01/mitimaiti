import cron from 'node-cron';
import { supabase } from './config/supabase';
import { redis } from './config/redis';
import { sendPush, flushBatchedLikes } from './services/notifications';
import { emitToUser } from './socket';

// ─── Every 5 minutes: Batch likes push ──────────────────────────────────────

const batchLikesJob = cron.schedule('*/5 * * * *', async () => {
  try {
    console.log('[Cron] Flushing batched like notifications...');
    await flushBatchedLikes();
  } catch (err) {
    console.error('[Cron] Batch likes flush error:', err);
  }
});

// ─── Every 15 minutes: Match expiry ─────────────────────────────────────────
// Dissolve matches where first_msg_at + 24h passed with no reply.
// Delete like rows. Push dissolution notification.
// Also send expiry_warning at 4h remaining.

const matchExpiryJob = cron.schedule('*/15 * * * *', async () => {
  try {
    const now = new Date();
    const nowISO = now.toISOString();

    // ── Phase 1: Expiry warnings (4 hours remaining) ─────────────────────
    // Matches where first_msg_at exists and first_msg_at + 20h < now < first_msg_at + 24h
    const fourHoursFromNow = new Date(now.getTime() + 4 * 60 * 60 * 1000).toISOString();
    const twentyHoursAgo = new Date(now.getTime() - 20 * 60 * 60 * 1000).toISOString();

    const { data: warningMatches } = await supabase
      .from('matches')
      .select('id, user_a_id, user_b_id, first_msg_by, first_msg_at')
      .eq('status', 'active')
      .not('first_msg_at', 'is', null)
      .lte('first_msg_at', twentyHoursAgo);

    for (const match of warningMatches || []) {
      // Check if we already sent a warning
      const warningKey = `expiry_warn:${match.id}`;
      const alreadyWarned = await redis.get(warningKey);
      if (alreadyWarned) continue;

      // Check if the first message has been replied to
      const receiverId = match.first_msg_by === match.user_a_id
        ? match.user_b_id
        : match.user_a_id;

      const { count: replyCount } = await supabase
        .from('messages')
        .select('*', { count: 'exact', head: true })
        .eq('match_id', match.id)
        .eq('sender_id', receiverId);

      // Only warn if no reply yet (match is at risk of expiring)
      if (!replyCount || replyCount === 0) {
        // Fetch names for notification
        const [{ data: userABasic }, { data: userBBasic }] = await Promise.all([
          supabase.from('basic_profiles').select('display_name').eq('user_id', match.user_a_id).single(),
          supabase.from('basic_profiles').select('display_name').eq('user_id', match.user_b_id).single(),
        ]);

        await Promise.all([
          sendPush(match.user_a_id, 'expiry_warning', {
            name: userBBasic?.display_name || 'your match',
            matchId: match.id,
          }),
          sendPush(match.user_b_id, 'expiry_warning', {
            name: userABasic?.display_name || 'your match',
            matchId: match.id,
          }),
        ]);

        await redis.set(warningKey, '1', 'EX', 86400);
      }
    }

    // ── Phase 2: Dissolve expired matches ────────────────────────────────
    // Matches where first_msg_at + 24h has passed with no reply
    const twentyFourHoursAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString();

    const { data: expiredMatches } = await supabase
      .from('matches')
      .select('id, user_a_id, user_b_id, first_msg_by, first_msg_at')
      .eq('status', 'active')
      .not('first_msg_at', 'is', null)
      .lte('first_msg_at', twentyFourHoursAgo);

    for (const match of expiredMatches || []) {
      // Check if receiver has replied
      const receiverId = match.first_msg_by === match.user_a_id
        ? match.user_b_id
        : match.user_a_id;

      const { count: replyCount } = await supabase
        .from('messages')
        .select('*', { count: 'exact', head: true })
        .eq('match_id', match.id)
        .eq('sender_id', receiverId);

      // Only dissolve if no reply
      if (!replyCount || replyCount === 0) {
        // Dissolve the match
        await supabase
          .from('matches')
          .update({
            status: 'dissolved',
            is_dissolved: true,
            dissolved_at: nowISO,
            // Column is dissolved_reason (what unmatch/block also write) —
            // dissolution_reason never existed
            dissolved_reason: 'expired_no_reply',
          })
          .eq('id', match.id);

        // Delete the like rows that created this match
        await supabase
          .from('actions')
          .delete()
          .or(`actor_id.eq.${match.user_a_id},actor_id.eq.${match.user_b_id}`)
          .or(`target_id.eq.${match.user_a_id},target_id.eq.${match.user_b_id}`)
          .eq('kind', 'like');

        // Fetch names for notification
        const [{ data: userABasic }, { data: userBBasic }] = await Promise.all([
          supabase.from('basic_profiles').select('display_name').eq('user_id', match.user_a_id).single(),
          supabase.from('basic_profiles').select('display_name').eq('user_id', match.user_b_id).single(),
        ]);

        // Push dissolution notification
        await Promise.all([
          sendPush(match.user_a_id, 'match_dissolved', {
            name: userBBasic?.display_name || 'your match',
            matchId: match.id,
          }),
          sendPush(match.user_b_id, 'match_dissolved', {
            name: userABasic?.display_name || 'your match',
            matchId: match.id,
          }),
        ]);

        // Clean up Redis expiry warning key
        await redis.del(`expiry_warn:${match.id}`);

        console.log(`[Cron] Dissolved expired match ${match.id}`);
      }
    }

    // ── Phase 3: Also dissolve matches with no first message after 48h ───
    const fortyEightHoursAgo = new Date(now.getTime() - 48 * 60 * 60 * 1000).toISOString();

    const { data: staleMatches } = await supabase
      .from('matches')
      .select('id, user_a_id, user_b_id')
      .eq('status', 'active')
      .is('first_msg_at', null)
      .lte('created_at', fortyEightHoursAgo);

    for (const match of staleMatches || []) {
      await supabase
        .from('matches')
        .update({
          status: 'dissolved',
          is_dissolved: true,
          dissolved_at: nowISO,
          dissolved_reason: 'expired_no_message',
        })
        .eq('id', match.id);

      await supabase
        .from('actions')
        .delete()
        .or(`actor_id.eq.${match.user_a_id},actor_id.eq.${match.user_b_id}`)
        .or(`target_id.eq.${match.user_a_id},target_id.eq.${match.user_b_id}`)
        .eq('kind', 'like');

      console.log(`[Cron] Dissolved stale match ${match.id} (no first message)`);
    }

    const warningCount = warningMatches?.length || 0;
    const expiredCount = expiredMatches?.length || 0;
    const staleCount = staleMatches?.length || 0;

    if (warningCount > 0 || expiredCount > 0 || staleCount > 0) {
      console.log(
        `[Cron] Match expiry: ${warningCount} warned, ${expiredCount} expired, ${staleCount} stale`
      );
    }
  } catch (err) {
    console.error('[Cron] Match expiry error:', err);
  }
});

// ─── Hourly: Passport expiry + ban lift ─────────────────────────────────────

const hourlyMaintenanceJob = cron.schedule('0 * * * *', async () => {
  try {
    const nowISO = new Date().toISOString();

    // ── Passport expiry: reset expired passports ─────────────────────────
    const { data: expiredPassports } = await supabase
      .from('user_privileges')
      .update({
        passport_city: null,
        passport_expires: null,
      })
      .not('passport_expires', 'is', null)
      .lte('passport_expires', nowISO)
      .select('user_id');

    if (expiredPassports && expiredPassports.length > 0) {
      console.log(`[Cron] Reset ${expiredPassports.length} expired passports`);
    }

    // ── Ban lift: lift time-based suspensions ────────────────────────────
    const { data: unsuspended } = await supabase
      .from('users')
      .update({
        is_suspended: false,
        ban_expires: null,
      })
      .eq('is_suspended', true)
      .not('ban_expires', 'is', null)
      .lte('ban_expires', nowISO)
      .select('id');

    // Lift temporary bans
    const { data: unbanned } = await supabase
      .from('users')
      .update({
        is_banned: false,
        is_active: true,
        ban_expires: null,
      })
      .eq('is_banned', true)
      .not('ban_expires', 'is', null)
      .lte('ban_expires', nowISO)
      .select('id');

    // Also update user_safety table
    if (unsuspended && unsuspended.length > 0) {
      for (const user of unsuspended) {
        await supabase
          .from('user_safety')
          .update({ is_suspended: false, suspension_until: null })
          .eq('user_id', user.id);
      }
    }

    const totalLifted = (unsuspended?.length || 0) + (unbanned?.length || 0);
    if (totalLifted > 0) {
      console.log(
        `[Cron] Lifted ${unsuspended?.length || 0} suspensions and ${unbanned?.length || 0} bans`
      );
    }
  } catch (err) {
    console.error('[Cron] Hourly maintenance error:', err);
  }
});

// ─── Midnight: Counter reset ────────────────────────────────────────────────
// Reset likes_used_today, rewinds_used_today in user_privileges

const dailyResetJob = cron.schedule('0 0 * * *', async () => {
  try {
    console.log('[Cron] Resetting daily counters...');

    // Reset all users' daily usage counters
    const { error } = await supabase
      .from('user_privileges')
      .update({
        likes_used_today: 0,
        rewinds_used_today: 0,
        last_reset_at: new Date().toISOString(),
      })
      .neq('user_id', '00000000-0000-0000-0000-000000000000'); // Match all rows

    if (error) {
      console.error('[Cron] Daily counter reset error:', error.message);
    } else {
      console.log('[Cron] Daily counters reset complete');
    }

    // Clear daily notification throttle keys from Redis
    let cursor = '0';
    do {
      const [newCursor, keys] = await redis.scan(
        cursor,
        'MATCH',
        'notif:*',
        'COUNT',
        500
      );
      cursor = newCursor;
      if (keys.length > 0) {
        // Only delete keys matching notif:{userId}:{date} pattern
        const dateKeys = keys.filter((k) => /^notif:[^:]+:\d{4}-\d{2}-\d{2}$/.test(k));
        if (dateKeys.length > 0) {
          await redis.del(...dateKeys);
        }
      }
    } while (cursor !== '0');
  } catch (err) {
    console.error('[Cron] Daily reset error:', err);
  }
});

// ─── Midnight: Daily prompt auto-pick ───────────────────────────────────────
// Auto-pick next prompt unless admin override

const dailyPromptJob = cron.schedule('0 0 * * *', async () => {
  try {
    const today = new Date().toISOString().split('T')[0];

    // Check if admin has already set an override for today
    const { data: existingPrompt } = await supabase
      .from('daily_prompts')
      .select('id')
      .eq('date', today)
      .eq('is_override', true)
      .maybeSingle();

    if (existingPrompt) {
      console.log('[Cron] Admin override prompt exists for today, skipping auto-pick');
      return;
    }

    // Deactivate yesterday's prompt
    const yesterday = new Date(Date.now() - 86400000).toISOString().split('T')[0];
    await supabase
      .from('daily_prompts')
      .update({ is_active: false })
      .eq('date', yesterday);

    // Check if a prompt is already scheduled for today
    const { data: scheduledPrompt } = await supabase
      .from('daily_prompts')
      .select('id, question')
      .eq('date', today)
      .eq('is_active', true)
      .maybeSingle();

    if (scheduledPrompt) {
      console.log(`[Cron] Today's prompt already set: "${scheduledPrompt.question}"`);
      return;
    }

    // Auto-pick: Get the next unused prompt from the pool
    const { data: nextPrompt } = await supabase
      .from('prompt_pool')
      .select('id, question, category')
      .eq('used', false)
      .order('sort_order', { ascending: true })
      .limit(1)
      .maybeSingle();

    if (nextPrompt) {
      // Activate this prompt for today
      await supabase.from('daily_prompts').insert({
        question: nextPrompt.question,
        category: nextPrompt.category,
        date: today,
        is_active: true,
        is_override: false,
      });

      // Mark it as used in the pool
      await supabase
        .from('prompt_pool')
        .update({ used: true })
        .eq('id', nextPrompt.id);

      console.log(`[Cron] Auto-picked today's prompt: "${nextPrompt.question}"`);
    } else {
      console.warn('[Cron] No unused prompts in pool. Reset the pool or add more.');
    }
  } catch (err) {
    console.error('[Cron] Daily prompt error:', err);
  }
});

// ─── 3 AM: Deletion + cleanup ───────────────────────────────────────────────
// Process 30-day delete queue, remove expired data

const cleanupJob = cron.schedule('0 3 * * *', async () => {
  try {
    console.log('[Cron] Running 3 AM cleanup...');

    const nowISO = new Date().toISOString();

    // ── Hard-delete accounts past 30-day grace period ────────────────────
    const { data: expiredAccounts } = await supabase
      .from('users')
      .select('id, auth_id')
      // Column is deletion_scheduled_for (what the delete-account flow in
      // auth.ts writes) — delete_scheduled_at never existed
      .not('deletion_scheduled_for', 'is', null)
      .lte('deletion_scheduled_for', nowISO);

    for (const account of expiredAccounts || []) {
      const userId = account.id;
      console.log(`[Cron] Hard deleting user ${userId}`);

      // Delete user data from all tables in parallel
      await Promise.all([
        supabase.from('basic_profiles').delete().eq('user_id', userId),
        supabase.from('sindhi_profiles').delete().eq('user_id', userId),
        supabase.from('chatti_profiles').delete().eq('user_id', userId),
        supabase.from('personality_profiles').delete().eq('user_id', userId),
        supabase.from('photos').delete().eq('user_id', userId),
        supabase.from('user_settings').delete().eq('user_id', userId),
        supabase.from('user_privileges').delete().eq('user_id', userId),
        supabase.from('user_safety').delete().eq('user_id', userId),
        supabase.from('user_fcm_tokens').delete().eq('user_id', userId),
        supabase.from('actions').delete().eq('actor_id', userId),
        supabase.from('blocked_users').delete().or(`blocker_id.eq.${userId},blocked_id.eq.${userId}`),
        supabase.from('family_access').delete().or(`owner_id.eq.${userId},family_user_id.eq.${userId}`),
        supabase.from('prompt_answers').delete().eq('user_id', userId),
        supabase.from('notif_log').delete().eq('user_id', userId),
        supabase.from('reports').delete().eq('reporter_id', userId),
        supabase.from('strikes').delete().eq('user_id', userId),
      ]);

      // Delete messages from matches this user was in
      const { data: userMatches } = await supabase
        .from('matches')
        .select('id')
        .or(`user_a_id.eq.${userId},user_b_id.eq.${userId}`);

      for (const match of userMatches || []) {
        await supabase.from('messages').delete().eq('match_id', match.id);
      }

      await supabase
        .from('matches')
        .delete()
        .or(`user_a_id.eq.${userId},user_b_id.eq.${userId}`);

      // Delete storage files
      const { data: storageList } = await supabase.storage
        .from('photos')
        .list(`users/${userId}/photos`);

      if (storageList && storageList.length > 0) {
        const paths = storageList.map((f) => `users/${userId}/photos/${f.name}`);
        await supabase.storage.from('photos').remove(paths);
      }

      // Delete the user record last
      await supabase.from('users').delete().eq('id', userId);

      // Delete auth user from Supabase Auth
      if (account.auth_id) {
        await supabase.auth.admin.deleteUser(account.auth_id);
      }

      // Clean up Redis
      await redis.del(
        `last_active:${userId}`,
        `online:${userId}`,
        `jwt_blacklist:${account.auth_id}`
      );
    }

    if ((expiredAccounts?.length || 0) > 0) {
      console.log(`[Cron] Hard deleted ${expiredAccounts!.length} accounts`);
    }

    // ── Clean old notification logs (older than 90 days) ─────────────────
    const ninetyDaysAgo = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000).toISOString();
    await supabase.from('notif_log').delete().lte('sent_at', ninetyDaysAgo);

    // ── Clean expired strikes ────────────────────────────────────────────
    const { data: expiredStrikes } = await supabase
      .from('strikes')
      .select('id, user_id')
      .eq('status', 'active')
      .not('expires_at', 'is', null)
      .lte('expires_at', nowISO);

    for (const strike of expiredStrikes || []) {
      await supabase
        .from('strikes')
        .update({ status: 'expired' })
        .eq('id', strike.id);
    }

    if ((expiredStrikes?.length || 0) > 0) {
      console.log(`[Cron] Expired ${expiredStrikes!.length} strikes`);
    }

    // ── Clean expired Redis keys (batch cleanup) ─────────────────────────
    // Redis TTLs handle most cleanup, but we also purge stale conversation cooldowns
    let cursor = '0';
    do {
      const [newCursor, keys] = await redis.scan(
        cursor,
        'MATCH',
        'notif_conv:*',
        'COUNT',
        200
      );
      cursor = newCursor;
      // These have TTLs, so we just let them expire naturally
    } while (cursor !== '0');

    console.log('[Cron] 3 AM cleanup complete');
  } catch (err) {
    console.error('[Cron] Cleanup error:', err);
  }
});

// ─── Start/Stop Functions ───────────────────────────────────────────────────

export function startCronJobs(): void {
  console.log('[Cron] Starting cron jobs...');
  batchLikesJob.start();
  matchExpiryJob.start();
  hourlyMaintenanceJob.start();
  dailyResetJob.start();
  dailyPromptJob.start();
  cleanupJob.start();
  console.log('[Cron] All cron jobs started');
}

export function stopCronJobs(): void {
  console.log('[Cron] Stopping cron jobs...');
  batchLikesJob.stop();
  matchExpiryJob.stop();
  hourlyMaintenanceJob.stop();
  dailyResetJob.stop();
  dailyPromptJob.stop();
  cleanupJob.stop();
  console.log('[Cron] All cron jobs stopped');
}

export default { startCronJobs, stopCronJobs };
