import * as admin from 'firebase-admin';
import { redis } from '../config/redis';
import { supabase } from '../config/supabase';
import { NotificationType, SAFETY_NOTIFICATION_TYPES } from '../types';

// ─── Firebase Admin Init ─────────────────────────────────────────────────────

if (!admin.apps.length) {
  const serviceAccount = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (serviceAccount) {
    admin.initializeApp({
      credential: admin.credential.cert(JSON.parse(serviceAccount)),
    });
  } else {
    // Falls back to GOOGLE_APPLICATION_CREDENTIALS env var
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
    });
  }
}

const messaging = admin.messaging();

// ─── Constants ───────────────────────────────────────────────────────────────

const MAX_DAILY_NOTIFICATIONS = 15;
const CONVERSATION_COOLDOWN_SECONDS = 180; // 3 minutes

// ─── Helpers ─────────────────────────────────────────────────────────────────

/**
 * Get today's date string for throttle keys (YYYY-MM-DD).
 */
function todayKey(): string {
  return new Date().toISOString().split('T')[0];
}

/**
 * Check if a notification type bypasses throttle (safety types).
 */
function isSafetyType(type: NotificationType): boolean {
  return SAFETY_NOTIFICATION_TYPES.includes(type);
}

// ─── Core Push Function ──────────────────────────────────────────────────────

/**
 * Send a push notification to a user.
 *
 * Flow:
 * 1. Check if user is online (online:{userId} in Redis) — skip push, use socket toast.
 * 2. Check daily throttle via Redis notif:{userId}:{date} (max 15/day).
 *    Safety types bypass throttle.
 * 3. Fetch FCM token from user_fcm_tokens table.
 * 4. Send via Firebase Admin SDK.
 * 5. Log to notif_log table.
 */
export async function sendPush(
  userId: string,
  type: NotificationType,
  data: Record<string, string> = {}
): Promise<boolean> {
  try {
    // 1. Skip push if user is currently online (they'll get a socket toast)
    const isOnline = await redis.exists(`online:${userId}`);
    if (isOnline) {
      console.log(`[Notifications] Skipped push (user online): ${type} for ${userId}`);
      return false;
    }

    // 2. Throttle check — safety types bypass
    if (!isSafetyType(type)) {
      const throttleKey = `notif:${userId}:${todayKey()}`;
      const currentCount = await redis.get(throttleKey);
      const count = currentCount ? parseInt(currentCount, 10) : 0;

      if (count >= MAX_DAILY_NOTIFICATIONS) {
        console.log(`[Notifications] Throttled (${count}/${MAX_DAILY_NOTIFICATIONS}): ${type} for ${userId}`);
        return false;
      }

      // Increment throttle counter
      const newCount = await redis.incr(throttleKey);
      if (newCount === 1) {
        // Set TTL to expire at end of day (max 24h)
        await redis.expire(throttleKey, 86400);
      }
    }

    // 3. Fetch FCM token (column is `token` — fcm_token never existed)
    const { data: tokenRow, error: tokenErr } = await supabase
      .from('user_fcm_tokens')
      .select('token')
      .eq('user_id', userId)
      .order('updated_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (tokenErr || !tokenRow?.token) {
      console.log(`[Notifications] No FCM token for user ${userId}`);
      return false;
    }

    // 4. Build and send Firebase message
    const title = data.title || formatTitle(type);
    const body = data.body || formatBody(type, data);

    const message: admin.messaging.Message = {
      token: tokenRow.token,
      notification: {
        title,
        body,
      },
      data: {
        type,
        ...data,
      },
      android: {
        priority: 'high',
        notification: {
          channelId: isSafetyType(type) ? 'safety' : 'default',
          sound: 'default',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
            'content-available': 1,
          },
        },
      },
    };

    const messageId = await messaging.send(message);
    console.log(`[Notifications] Sent ${type} to ${userId}: ${messageId}`);

    // 5. Log to notif_log
    await supabase.from('notif_log').insert({
      user_id: userId,
      type,
      title,
      body,
      data,
      fcm_message_id: messageId,
      sent_at: new Date().toISOString(),
    });

    return true;
  } catch (err: any) {
    // Handle invalid token (unregistered device)
    if (
      err.code === 'messaging/registration-token-not-registered' ||
      err.code === 'messaging/invalid-registration-token'
    ) {
      console.warn(`[Notifications] Removing stale FCM token for user ${userId}`);
      await supabase
        .from('user_fcm_tokens')
        .delete()
        .eq('user_id', userId);
      return false;
    }

    console.error(`[Notifications] Failed to send ${type} to ${userId}:`, err.message || err);
    return false;
  }
}

// ─── Conversation Cooldown ───────────────────────────────────────────────────

/**
 * Check and set 3-minute conversation cooldown.
 * Prevents spamming push notifications for rapid-fire messages in a match.
 *
 * @returns true if cooldown is clear (notification can be sent)
 */
export async function checkConversationCooldown(
  matchId: string,
  userId: string
): Promise<boolean> {
  const cooldownKey = `notif_conv:${matchId}:${userId}`;
  const exists = await redis.exists(cooldownKey);

  if (exists) {
    return false; // Still in cooldown
  }

  // Set cooldown
  await redis.set(cooldownKey, '1', 'EX', CONVERSATION_COOLDOWN_SECONDS);
  return true;
}

// ─── Batched Likes ───────────────────────────────────────────────────────────

/**
 * Queue a like notification for batching.
 * The cron job flushes these every 5 minutes.
 */
export async function queueLikeNotification(userId: string): Promise<void> {
  const key = `notif_batch_likes:${userId}`;
  await redis.incr(key);
  const ttl = await redis.ttl(key);
  if (ttl === -1) {
    await redis.expire(key, 300); // 5 minute window
  }
}

/**
 * Flush batched like notifications. Called by cron every 5 minutes.
 * Groups 5+ pending likes into a single notification.
 */
export async function flushBatchedLikes(): Promise<void> {
  let cursor = '0';
  do {
    const [newCursor, keys] = await redis.scan(
      cursor,
      'MATCH',
      'notif_batch_likes:*',
      'COUNT',
      100
    );
    cursor = newCursor;

    for (const key of keys) {
      const countStr = await redis.get(key);
      if (!countStr) continue;

      const likeCount = parseInt(countStr, 10);
      if (likeCount < 5) continue; // Only batch 5+ likes

      const userId = key.replace('notif_batch_likes:', '');

      await sendPush(userId, 'likes_batch', {
        title: `${likeCount} New Likes!`,
        body: `${likeCount} people liked your profile. Open to see who!`,
        likeCount: likeCount.toString(),
      });

      await redis.del(key);
    }
  } while (cursor !== '0');
}

// ─── Title / Body Formatters ─────────────────────────────────────────────────

function formatTitle(type: NotificationType): string {
  const titles: Record<NotificationType, string> = {
    like_received: 'New Like!',
    likes_batch: 'New Likes!',
    match_created: "It's a Match!",
    new_match: "It's a Match!",
    message_received: 'New Message',
    new_message: 'New Message',
    voice_message: 'New Voice Message',
    photo_received: 'New Photo',
    expiry_warning: 'Match Expiring Soon',
    match_expiring: 'Match Expiring Soon',
    match_dissolved: 'Match Ended',
    incoming_call: 'Incoming Call',
    family_joined: 'Family Member Joined',
    family_suggestion: 'New Family Suggestion',
    suggestion_reviewed: 'Suggestion Reviewed',
    access_revoked: 'Access Updated',
    profile_verified: 'Profile Verified!',
    snooze_ended: 'Welcome Back!',
    deletion_reminder: 'Account Deletion Reminder',
    profile_nudge: 'Complete Your Profile',
    strike_issued: 'Account Warning',
    appeal_resolved: 'Appeal Resolved',
  };

  return titles[type] || 'MitiMaiti';
}

function formatBody(type: NotificationType, data: Record<string, string>): string {
  const name = data.name || 'Someone';

  const bodies: Record<NotificationType, string> = {
    like_received: `${name} liked your profile`,
    likes_batch: 'Multiple people liked your profile',
    match_created: `You and ${name} liked each other!`,
    new_match: `You and ${name} liked each other!`,
    message_received: `${name} sent you a message`,
    new_message: `${name} sent you a message`,
    voice_message: `${name} sent you a voice message`,
    photo_received: `${name} sent you a photo`,
    expiry_warning: `Your match with ${name} is expiring soon. Send a message!`,
    match_expiring: `Your match with ${name} is expiring soon. Send a message!`,
    match_dissolved: `Your match with ${name} has ended`,
    incoming_call: `${name} is calling you`,
    family_joined: `${name} joined your family account`,
    family_suggestion: `Your family suggested a new match for you`,
    suggestion_reviewed: 'Your family suggestion has been reviewed',
    access_revoked: 'Your family access permissions have been updated',
    profile_verified: 'Congratulations! Your profile has been verified.',
    snooze_ended: 'Your snooze has ended. Ready to meet someone new?',
    deletion_reminder: 'Your account is scheduled for deletion. Sign in to cancel.',
    profile_nudge: 'Complete your profile to get more matches!',
    strike_issued: 'Your account has received a community guideline warning.',
    appeal_resolved: 'Your appeal has been reviewed. Check the app for details.',
  };

  return bodies[type] || 'You have a new notification';
}

// ─── Backward-Compatible Template Helper ─────────────────────────────────────

/**
 * Send notification using template defaults with optional placeholder replacements.
 * Wraps sendPush for backward compatibility with routes that use this pattern.
 */
export async function sendTemplateNotification(
  type: NotificationType,
  userId: string,
  replacements: Record<string, string> = {},
  extraData: Record<string, string> = {}
): Promise<boolean> {
  let title = formatTitle(type);
  let body = formatBody(type, replacements);

  // Replace any remaining placeholders
  for (const [key, value] of Object.entries(replacements)) {
    title = title.replace(`{${key}}`, value);
    body = body.replace(`{${key}}`, value);
  }

  return sendPush(userId, type, { ...extraData, ...replacements, title, body });
}

export default {
  sendPush,
  sendTemplateNotification,
  checkConversationCooldown,
  queueLikeNotification,
  flushBatchedLikes,
};
