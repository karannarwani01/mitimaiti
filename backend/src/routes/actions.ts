import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { supabase } from '../config/supabase';
import { redis } from '../config/redis';
import { AppError, asyncHandler } from '../utils/errors';
import { authenticate } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { getCulturalScore } from '../services/scoring';
import { sendTemplateNotification, queueLikeNotification } from '../services/notifications';
import { AuthenticatedRequest, ActionType, CulturalBadge } from '../types';

const router = Router();

// ─── Constants ──────────────────────────────────────────────────────────────────

const DAILY_LIKE_LIMIT = 50;
const DAILY_REWIND_LIMIT = 10;
const MATCH_EXPIRY_HOURS = 24;

// ─── Schemas ────────────────────────────────────────────────────────────────────

const actionSchema = z.object({
  target_user_id: z.string().uuid('Invalid target user ID'),
  type: z.enum(['like', 'pass']),
});

const promptSchema = z.object({
  answer: z.string().min(1, 'Answer is required').max(500, 'Answer must be 500 characters or less'),
});

// ─── Helpers ────────────────────────────────────────────────────────────────────

/**
 * Get today's date key for daily limit tracking (YYYY-MM-DD).
 */
function todayKey(): string {
  return new Date().toISOString().split('T')[0];
}

/**
 * Get daily usage count from Redis with PostgreSQL fallback.
 */
async function getDailyCount(userId: string, actionType: string): Promise<number> {
  const key = `daily_${actionType}:${userId}:${todayKey()}`;

  try {
    const cached = await redis.get(key);
    if (cached !== null) {
      return parseInt(cached, 10);
    }
  } catch {
    // Redis down — fall through to DB count
  }

  // Fallback: count from database
  const todayStart = `${todayKey()}T00:00:00.000Z`;
  const { count } = await supabase
    .from('actions')
    .select('*', { count: 'exact', head: true })
    .eq('actor_id', userId)
    .eq('kind', actionType)
    .gte('created_at', todayStart);

  return count || 0;
}

/**
 * Increment daily usage count in Redis. Sets TTL to end of day.
 */
async function incrementDailyCount(userId: string, actionType: string): Promise<void> {
  const key = `daily_${actionType}:${userId}:${todayKey()}`;

  try {
    const count = await redis.incr(key);
    if (count === 1) {
      // Set expiry to end of day (max 24 hours)
      const now = new Date();
      const endOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
      const ttl = Math.ceil((endOfDay.getTime() - now.getTime()) / 1000);
      await redis.expire(key, ttl);
    }
  } catch {
    // Redis down — counts will be recounted from DB on next check
  }
}

/**
 * Invalidate the user's cached feed so rewound/new profiles appear.
 */
async function invalidateFeedCache(userId: string): Promise<void> {
  try {
    await redis.del(`feed_cache:${userId}`);
  } catch {
    // Non-critical
  }
}

function calculateAge(dob: string): number {
  const birth = new Date(dob);
  const today = new Date();
  let age = today.getFullYear() - birth.getFullYear();
  const monthDiff = today.getMonth() - birth.getMonth();
  if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birth.getDate())) {
    age--;
  }
  return age;
}

// ─── POST /v1/action ────────────────────────────────────────────────────────────

router.post(
  '/',
  authenticate,
  validate(actionSchema),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const { target_user_id: targetUserId, type } = req.body as { target_user_id: string; type: ActionType };

    // Self-action guard
    if (targetUserId === user.id) {
      throw new AppError(400, 'Cannot perform action on yourself', 'SELF_ACTION');
    }

    // Verify target exists and is not banned/inactive
    const { data: target } = await supabase
      .from('users')
      .select('id, is_active, is_banned')
      .eq('id', targetUserId)
      .single();

    if (!target || !target.is_active || target.is_banned) {
      throw new AppError(404, 'User not found or unavailable', 'TARGET_NOT_FOUND');
    }

    // Block check (both directions)
    const { data: block } = await supabase
      .from('blocked_users')
      .select('id')
      .or(
        `and(blocker_id.eq.${user.id},blocked_id.eq.${targetUserId}),and(blocker_id.eq.${targetUserId},blocked_id.eq.${user.id})`,
      )
      .limit(1)
      .maybeSingle();

    if (block) {
      throw new AppError(403, 'Cannot interact with this user', 'BLOCKED');
    }

    // Duplicate action check (prevent double-like, but allow re-pass)
    if (type === 'like') {
      const { data: existingLike } = await supabase
        .from('actions')
        .select('id')
        .eq('actor_id', user.id)
        .eq('target_id', targetUserId)
        .eq('kind', 'like')
        .limit(1)
        .maybeSingle();

      if (existingLike) {
        throw new AppError(409, 'You have already liked this profile', 'DUPLICATE_LIKE');
      }
    }

    // ── Daily like limit: 50 per day ────────────────────────────────────────

    if (type === 'like') {
      const likesUsed = await getDailyCount(user.id, 'like');
      if (likesUsed >= DAILY_LIKE_LIMIT) {
        throw new AppError(
          429,
          `Daily like limit reached (${DAILY_LIKE_LIMIT}). Try again tomorrow.`,
          'DAILY_LIMIT_REACHED',
        );
      }
    }

    // ── Atomic INSERT into actions table ────────────────────────────────────

    const { data: action, error: actionError } = await supabase
      .from('actions')
      .insert({
        actor_id: user.id,
        target_id: targetUserId,
        kind: type,
      })
      .select('id, created_at')
      .single();

    if (actionError) {
      // Handle unique constraint violation (race condition double-like)
      if (actionError.code === '23505') {
        throw new AppError(409, 'Action already recorded', 'DUPLICATE_ACTION');
      }
      throw new AppError(500, 'Failed to record action', 'ACTION_FAILED');
    }

    // Increment daily counter
    await incrementDailyCount(user.id, type);

    // Invalidate feed cache
    await invalidateFeedCache(user.id);

    // ── Mutual match detection (only for likes) ────────────────────────────

    let isMatch = false;
    let matchId: string | null = null;
    let matchExpiresAt: string | null = null;

    if (type === 'like') {
      // Check if target has liked us
      const { data: reciprocal } = await supabase
        .from('actions')
        .select('id')
        .eq('actor_id', targetUserId)
        .eq('target_id', user.id)
        .eq('kind', 'like')
        .limit(1)
        .maybeSingle();

      if (reciprocal) {
        isMatch = true;

        // Get cultural score for the match record
        let culturalScore = 0;
        try {
          const cs = await getCulturalScore(user.id, targetUserId);
          culturalScore = cs.total;
        } catch {
          // Continue without score
        }

        // Create match with 24-hour expiry for first message
        const expiresAt = new Date();
        expiresAt.setHours(expiresAt.getHours() + MATCH_EXPIRY_HOURS);
        matchExpiresAt = expiresAt.toISOString();

        // Canonical ID ordering for match
        const [userA, userB] = user.id < targetUserId
          ? [user.id, targetUserId]
          : [targetUserId, user.id];

        // Check if match already exists (race condition guard)
        const { data: existingMatch } = await supabase
          .from('matches')
          .select('id')
          .eq('user_a_id', userA)
          .eq('user_b_id', userB)
          .limit(1)
          .maybeSingle();

        if (existingMatch) {
          matchId = existingMatch.id;
        } else {
          const { data: match, error: matchError } = await supabase
            .from('matches')
            .insert({
              user_a_id: userA,
              user_b_id: userB,
              status: 'pending_first_message',
              matched_at: new Date().toISOString(),
              expires_at: matchExpiresAt,
              cultural_score: culturalScore,
            })
            .select('id')
            .single();

          if (matchError) {
            console.error('[Actions] Failed to create match:', matchError.message);
          } else {
            matchId = match.id;
          }
        }

        // Send match notifications to both users
        const [{ data: myBasic }, { data: targetBasic }] = await Promise.all([
          supabase.from('basic_profiles').select('display_name').eq('user_id', user.id).single(),
          supabase.from('basic_profiles').select('display_name').eq('user_id', targetUserId).single(),
        ]);

        await Promise.all([
          sendTemplateNotification('new_match', user.id, {
            name: targetBasic?.display_name || 'Someone',
          }),
          sendTemplateNotification('new_match', targetUserId, {
            name: myBasic?.display_name || 'Someone',
          }),
        ]).catch((err) => {
          console.error('[Actions] Failed to send match notifications:', err);
        });

        // Invalidate both users' feed caches
        await invalidateFeedCache(targetUserId);
      } else {
        // Not a match yet — queue like notification
        await queueLikeNotification(targetUserId).catch(() => {});
      }
    }

    res.status(201).json({
      success: true,
      data: {
        action_id: action.id,
        type,
        is_match: isMatch,
        match_id: matchId,
        match_expires_at: matchExpiresAt,
        created_at: action.created_at,
      },
    });
  }),
);

// ─── POST /v1/action/rewind ─────────────────────────────────────────────────────

router.post(
  '/rewind',
  authenticate,
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;

    // ── Daily rewind limit: 10 per day ──────────────────────────────────────

    const rewindsUsed = await getDailyCount(user.id, 'rewind');
    if (rewindsUsed >= DAILY_REWIND_LIMIT) {
      throw new AppError(
        429,
        `Daily rewind limit reached (${DAILY_REWIND_LIMIT}). Try again tomorrow.`,
        'REWIND_LIMIT_REACHED',
      );
    }

    // ── Find last pass action (NOT likes — rewind only works on passes) ─────

    const { data: lastPass } = await supabase
      .from('actions')
      .select('id, target_id, kind, created_at')
      .eq('actor_id', user.id)
      .eq('kind', 'pass')
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (!lastPass) {
      throw new AppError(404, 'No recent pass to rewind', 'NO_PASS_TO_REWIND');
    }

    // ── Delete the pass record ──────────────────────────────────────────────

    const { error: deleteError } = await supabase
      .from('actions')
      .delete()
      .eq('id', lastPass.id);

    if (deleteError) {
      throw new AppError(500, 'Failed to rewind pass', 'REWIND_FAILED');
    }

    // Track the rewind in daily counters
    await incrementDailyCount(user.id, 'rewind');

    // Invalidate feed cache so the rewound profile reappears
    await invalidateFeedCache(user.id);

    const rewindsRemaining = DAILY_REWIND_LIMIT - rewindsUsed - 1;

    res.json({
      success: true,
      data: {
        rewound_target_id: lastPass.target_id,
        rewinds_remaining: rewindsRemaining,
        rewinds_used_today: rewindsUsed + 1,
      },
    });
  }),
);

// ─── POST /v1/action/prompt ─────────────────────────────────────────────────────

router.post(
  '/prompt',
  authenticate,
  validate(promptSchema),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const { answer } = req.body;

    // Update daily_prompt_answer on the users table
    const { error: updateError } = await supabase
      .from('users')
      .update({
        daily_prompt_answer: answer,
        daily_prompt_answered_at: new Date().toISOString(),
      })
      .eq('id', user.id);

    if (updateError) {
      throw new AppError(500, 'Failed to save prompt answer', 'PROMPT_SAVE_FAILED');
    }

    // Invalidate feed cache so other users see the updated prompt
    await invalidateFeedCache(user.id);

    res.json({
      success: true,
      data: {
        answer,
        answered_at: new Date().toISOString(),
      },
    });
  }),
);

// ─── GET /v1/inbox ──────────────────────────────────────────────────────────────
// Mounted at /v1/inbox via server.ts, so this is GET /v1/inbox

router.get(
  '/',
  authenticate,
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;

    // Fetch user's gender preference to filter inbox results
    const { data: mySettings } = await supabase
      .from('user_settings')
      .select('gender_preference')
      .eq('user_id', user.id)
      .maybeSingle();

    const genderPref = mySettings?.gender_preference || 'everyone';
    const preferredGender = genderPref === 'men' ? 'man' : genderPref === 'women' ? 'woman' : null;

    // ── Section 1: Users who liked me (NOT blurred — every user is equal) ───

    // Get all likes targeting current user
    const { data: incomingLikes } = await supabase
      .from('actions')
      .select('id, actor_id, created_at')
      .eq('target_id', user.id)
      .eq('kind', 'like')
      .order('created_at', { ascending: false });

    // Filter out anyone I've already acted on: likes became matches, and passes
    // were declined — neither should remain a pending like.
    const { data: myActions } = await supabase
      .from('actions')
      .select('target_id')
      .eq('actor_id', user.id)
      .in('kind', ['like', 'pass']);

    const myActedIds = new Set<string>(
      (myActions || []).map((l: any) => l.target_id),
    );

    const pendingLikes = (incomingLikes || []).filter(
      (l: any) => !myActedIds.has(l.actor_id),
    );

    // Enrich pending likes with full profile cards (NOT blurred)
    const likerIds = pendingLikes.map((l: any) => l.actor_id);
    let likedYouCards: any[] = [];

    if (likerIds.length > 0) {
      const [
        { data: likerProfiles },
        { data: likerUsers },
        { data: likerPhotos },
        { data: likerPersonality },
      ] = await Promise.all([
        supabase
          .from('basic_profiles')
          .select('user_id, display_name, date_of_birth, gender, city, intent, bio, education, occupation')
          .in('user_id', likerIds),
        supabase
          .from('users')
          .select('id, is_verified, daily_prompt_answer')
          .in('id', likerIds),
        supabase
          .from('photos')
          .select('user_id, url_medium, url_original, sort_order')
          .in('user_id', likerIds)
          .order('sort_order'),
        supabase
          .from('personality_profiles')
          .select('user_id, interests')
          .in('user_id', likerIds),
      ]);

      const likerProfileMap = new Map<string, any>();
      (likerProfiles || []).forEach((p: any) => likerProfileMap.set(p.user_id, p));

      const likerUserMap = new Map<string, any>();
      (likerUsers || []).forEach((u: any) => likerUserMap.set(u.id, u));

      const likerPhotoMap = new Map<string, any[]>();
      (likerPhotos || []).forEach((p: any) => {
        if (!likerPhotoMap.has(p.user_id)) likerPhotoMap.set(p.user_id, []);
        likerPhotoMap.get(p.user_id)!.push(p);
      });

      const likerInterestMap = new Map<string, string[]>();
      (likerPersonality || []).forEach((p: any) => {
        likerInterestMap.set(p.user_id, p.interests || []);
      });

      // Get cultural scores for each liker
      const culturalScores = await Promise.allSettled(
        likerIds.map(async (likerId: string) => {
          try {
            const cs = await getCulturalScore(user.id, likerId);
            return { userId: likerId, total: cs.total, badge: cs.badge };
          } catch {
            return { userId: likerId, total: 0, badge: 'none' as CulturalBadge };
          }
        }),
      );

      const csMap = new Map<string, { total: number; badge: CulturalBadge }>();
      for (const result of culturalScores) {
        if (result.status === 'fulfilled') {
          csMap.set(result.value.userId, { total: result.value.total, badge: result.value.badge });
        }
      }

      // Build liked_you cards — full profile, NOT blurred
      for (const like of pendingLikes) {
        const profile = likerProfileMap.get(like.actor_id);
        const userMeta = likerUserMap.get(like.actor_id);
        const photos = likerPhotoMap.get(like.actor_id) || [];
        const interests = likerInterestMap.get(like.actor_id) || [];
        const cs = csMap.get(like.actor_id) || { total: 0, badge: 'none' as CulturalBadge };

        if (!profile) continue;

        // Skip profiles that don't match gender preference
        if (preferredGender && profile.gender !== preferredGender) continue;

        likedYouCards.push({
          id: like.actor_id,
          action_id: like.id,
          first_name: profile.display_name?.split(' ')[0] || 'Unknown',
          display_name: profile.display_name || 'Unknown',
          age: profile.date_of_birth ? calculateAge(profile.date_of_birth) : null,
          city: profile.city,
          intent: profile.intent,
          is_verified: userMeta?.is_verified || false,
          photos: photos.map((p: any) => ({
            url: p.url_original,
            url_thumb: p.url_medium,
            url_medium: p.url_medium,
            is_primary: p.is_primary || false,
            sort_order: p.sort_order || 0,
            is_verified: false,
            is_video: false,
          })),
          about_me: profile.bio || null,
          interests,
          cultural_score: cs.total,
          cultural_badge: cs.badge,
          like_label: 'Liked your profile',
          daily_prompt_answer: userMeta?.daily_prompt_answer || null,
          liked_at: like.created_at,
        });
      }
    }

    // ── Section 2: Active matches with countdown data ───────────────────────

    const { data: matches } = await supabase
      .from('matches')
      .select('*')
      .or(`user_a_id.eq.${user.id},user_b_id.eq.${user.id}`)
      .in('status', ['active', 'pending_first_message'])
      .order('matched_at', { ascending: false });

    const matchItems: any[] = [];

    if (matches && matches.length > 0) {
      const otherIds = matches.map((m: any) =>
        m.user_a_id === user.id ? m.user_b_id : m.user_a_id,
      );

      const [
        { data: matchProfiles },
        { data: matchUsers },
        { data: matchPhotos },
      ] = await Promise.all([
        supabase
          .from('basic_profiles')
          .select('user_id, display_name, gender, city, date_of_birth')
          .in('user_id', otherIds),
        supabase
          .from('users')
          .select('id, is_verified')
          .in('id', otherIds),
        supabase
          .from('photos')
          .select('user_id, url_medium, url_original, is_primary, sort_order')
          .in('user_id', otherIds)
          .eq('is_primary', true)
          .limit(otherIds.length),
      ]);

      const matchProfileMap = new Map<string, any>();
      (matchProfiles || []).forEach((p: any) => matchProfileMap.set(p.user_id, p));

      const matchUserMap = new Map<string, any>();
      (matchUsers || []).forEach((u: any) => matchUserMap.set(u.id, u));

      const matchPhotoMap = new Map<string, any>();
      (matchPhotos || []).forEach((p: any) => {
        if (!matchPhotoMap.has(p.user_id)) matchPhotoMap.set(p.user_id, p);
      });

      for (const match of matches) {
        const otherId = match.user_a_id === user.id ? match.user_b_id : match.user_a_id;
        const profile = matchProfileMap.get(otherId);
        const userMeta = matchUserMap.get(otherId);
        const photo = matchPhotoMap.get(otherId);

        // Skip profiles that don't match gender preference
        if (preferredGender && profile?.gender !== preferredGender) continue;

        // Get last message for this match
        const { data: lastMessage } = await supabase
          .from('messages')
          .select('content, created_at, sender_id, msg_type')
          .eq('match_id', match.id)
          .order('created_at', { ascending: false })
          .limit(1)
          .maybeSingle();

        // Count unread messages
        const { count: unreadCount } = await supabase
          .from('messages')
          .select('*', { count: 'exact', head: true })
          .eq('match_id', match.id)
          .neq('sender_id', user.id)
          .is('read_at', null);

        // Compute countdown timer for pending first message
        let countdown: { expires_at: string; seconds_remaining: number } | null = null;
        if (match.status === 'pending_first_message' && match.expires_at) {
          const expiresAt = new Date(match.expires_at);
          const secondsRemaining = Math.max(0, Math.floor((expiresAt.getTime() - Date.now()) / 1000));
          countdown = {
            expires_at: match.expires_at,
            seconds_remaining: secondsRemaining,
          };
        }

        matchItems.push({
          match_id: match.id,
          user_id: otherId,
          first_name: profile?.display_name?.split(' ')[0] || 'Unknown',
          display_name: profile?.display_name || 'Unknown',
          age: profile?.date_of_birth ? calculateAge(profile.date_of_birth) : null,
          city: profile?.city || null,
          is_verified: userMeta?.is_verified || false,
          photo: photo
            ? { url: photo.url_original, url_thumb: photo.url_medium, url_medium: photo.url_medium }
            : null,
          cultural_score: match.cultural_score || 0,
          status: match.status,
          matched_at: match.matched_at || match.created_at,
          expires_at: match.expires_at || null,
          first_msg_by: match.first_msg_by || null,
          // Server-computed: did the current user send the first message?
          // Clients use this for the Respect-First lock instead of comparing ids.
          first_msg_by_me: match.first_msg_by != null && match.first_msg_by === user.id,
          first_msg_locked: match.first_msg_locked || false,
          first_msg_at: match.first_msg_at || null,
          countdown,
          last_message: lastMessage
            ? {
                content: lastMessage.content,
                sent_at: lastMessage.created_at,
                is_you: lastMessage.sender_id === user.id,
                msg_type: lastMessage.msg_type,
              }
            : null,
          unread_count: unreadCount || 0,
        });
      }

      // Sort matches: unread first, then by last activity
      matchItems.sort((a, b) => {
        // Unread messages first
        if (a.unread_count > 0 && b.unread_count === 0) return -1;
        if (a.unread_count === 0 && b.unread_count > 0) return 1;

        // Then by last message time (or matched_at if no messages)
        const aTime = a.last_message?.sent_at || a.matched_at;
        const bTime = b.last_message?.sent_at || b.matched_at;
        return new Date(bTime).getTime() - new Date(aTime).getTime();
      });
    }

    res.json({
      success: true,
      data: {
        liked_you: {
          count: likedYouCards.length,
          profiles: likedYouCards,
        },
        matches: {
          count: matchItems.length,
          profiles: matchItems,
        },
      },
    });
  }),
);

export default router;
