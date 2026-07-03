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

export const DAILY_LIKE_LIMIT = 50;
export const DAILY_REWIND_LIMIT = 10;
export const DAILY_COMMENT_LIMIT = 5;
const MATCH_EXPIRY_HOURS = 24;

// ─── Schemas ────────────────────────────────────────────────────────────────────

const actionSchema = z
  .object({
    target_user_id: z.string().uuid('Invalid target user ID'),
    type: z.enum(['like', 'pass']),
    comment: z
      .string()
      .trim()
      .min(1, 'Comment cannot be empty')
      .max(280, 'Comment must be 280 characters or less')
      .optional(),
  })
  .refine((data) => !(data.comment && data.type === 'pass'), {
    message: 'A comment can only accompany a like',
    path: ['comment'],
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

// Migration 007 adds actions.comment. Until it is applied in Supabase the
// column is absent, so every comment-bearing query must degrade to the plain
// like path. Cache the "missing" result briefly so we don't pay a failed
// round-trip per request, but recheck so the feature switches on by itself
// once the migration lands.
let commentColumnMissingUntil = 0;
const COMMENT_COLUMN_RECHECK_MS = 5 * 60 * 1000;

function commentColumnKnownMissing(): boolean {
  return Date.now() < commentColumnMissingUntil;
}

function isMissingCommentColumnError(err: { code?: string; message?: string } | null): boolean {
  if (!err) return false;
  if (err.code === '42703' || err.code === 'PGRST204') {
    return /comment/i.test(err.message || '');
  }
  return false;
}

function markCommentColumnMissing(): void {
  commentColumnMissingUntil = Date.now() + COMMENT_COLUMN_RECHECK_MS;
  console.warn(
    '[Actions] actions.comment column missing — apply supabase/migrations/007_like_comments.sql. Degrading to plain likes.',
  );
}

/**
 * Get daily usage count from Redis with PostgreSQL fallback.
 * Exported so the feed can seed clients with server-authoritative counters.
 */
export async function getDailyCount(userId: string, actionType: string): Promise<number> {
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

  // 'comment' is not an action kind — it rides on likes. Count today's
  // commented likes instead. Pre-migration-007 this errors (no column) and
  // we treat usage as 0, which is safe because comments aren't persisted yet.
  if (actionType === 'comment') {
    const { count, error } = await supabase
      .from('actions')
      .select('*', { count: 'exact', head: true })
      .eq('actor_id', userId)
      .eq('kind', 'like')
      .not('comment', 'is', null)
      .gte('created_at', todayStart);
    if (error) {
      if (isMissingCommentColumnError(error)) markCommentColumnMissing();
      return 0;
    }
    return count || 0;
  }

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
    const { target_user_id: targetUserId, type, comment } = req.body as {
      target_user_id: string;
      type: ActionType;
      comment?: string;
    };

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
    // blocked_users has no id column (composite key) — selecting id made this
    // check silently no-op
    const { data: block } = await supabase
      .from('blocked_users')
      .select('blocker_id')
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

    let likesUsed = 0;
    if (type === 'like') {
      likesUsed = await getDailyCount(user.id, 'like');
      if (likesUsed >= DAILY_LIKE_LIMIT) {
        throw new AppError(
          429,
          `Daily like limit reached (${DAILY_LIKE_LIMIT}). Try again tomorrow.`,
          'DAILY_LIMIT_REACHED',
        );
      }
    }

    // ── Daily comment limit: 5 per day (Hinge-style like-with-comment) ──────

    let commentsUsed = 0;
    const wantsComment = type === 'like' && !!comment;
    if (wantsComment) {
      commentsUsed = await getDailyCount(user.id, 'comment');
      if (commentsUsed >= DAILY_COMMENT_LIMIT) {
        throw new AppError(
          429,
          `Daily comment limit reached (${DAILY_COMMENT_LIMIT}). Your like can still be sent without a comment.`,
          'COMMENT_LIMIT_REACHED',
        );
      }
    }

    // ── Atomic INSERT into actions table ────────────────────────────────────
    // If migration 007 hasn't been applied yet, retry without the comment so
    // the like itself never fails; the client is told via comment_saved.

    let commentSaved = wantsComment && !commentColumnKnownMissing();

    const insertAction = (withComment: boolean) =>
      supabase
        .from('actions')
        .insert({
          actor_id: user.id,
          target_id: targetUserId,
          kind: type,
          ...(withComment ? { comment } : {}),
        })
        .select('id, created_at')
        .single();

    let { data: action, error: actionError } = await insertAction(commentSaved);

    if (actionError && commentSaved && isMissingCommentColumnError(actionError)) {
      markCommentColumnMissing();
      commentSaved = false;
      ({ data: action, error: actionError } = await insertAction(false));
    }

    if (actionError || !action) {
      // Handle unique constraint violation (race condition double-like)
      if (actionError?.code === '23505') {
        throw new AppError(409, 'Action already recorded', 'DUPLICATE_ACTION');
      }
      throw new AppError(500, 'Failed to record action', 'ACTION_FAILED');
    }

    // Increment daily counters
    await incrementDailyCount(user.id, type);
    if (commentSaved) {
      await incrementDailyCount(user.id, 'comment');
    }

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

        // Check if match already exists (race condition guard). The pair has
        // a unique (user_a_id, user_b_id) row, so a re-match after an
        // unmatch/expiry must REVIVE the dissolved row — returning it as-is
        // handed clients a dead match (status=dissolved) where extend and
        // every message 403'd.
        const { data: existingMatch } = await supabase
          .from('matches')
          .select('id, status, is_dissolved')
          .eq('user_a_id', userA)
          .eq('user_b_id', userB)
          .limit(1)
          .maybeSingle();

        if (existingMatch) {
          matchId = existingMatch.id;
          if (existingMatch.is_dissolved || ['dissolved', 'expired', 'unmatched'].includes(existingMatch.status)) {
            const { error: reviveError } = await supabase
              .from('matches')
              .update({
                status: 'pending_first_message',
                is_dissolved: false,
                dissolved_at: null,
                dissolved_reason: null,
                matched_at: new Date().toISOString(),
                expires_at: matchExpiresAt,
                first_msg_by: null,
                first_msg_at: null,
                first_msg_locked: false,
                extended_once: false,
                cultural_score: culturalScore,
              })
              .eq('id', existingMatch.id);
            if (reviveError) {
              console.error('[Actions] Failed to revive dissolved match:', reviveError.message);
            }
          }
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
            // Likely a concurrent reciprocal like created the row between our
            // existence check and this insert — re-select instead of returning
            // is_match:true with a null match_id.
            console.error('[Actions] Failed to create match:', matchError.message);
            const { data: racedMatch } = await supabase
              .from('matches')
              .select('id, expires_at')
              .eq('user_a_id', userA)
              .eq('user_b_id', userB)
              .limit(1)
              .maybeSingle();
            if (racedMatch) {
              matchId = racedMatch.id;
              matchExpiresAt = racedMatch.expires_at || matchExpiresAt;
            } else {
              isMatch = false;
              matchExpiresAt = null;
            }
          } else {
            matchId = match.id;
          }
        }

        // Send match notifications to both users
        const [{ data: myBasic }, { data: targetBasic }] = await Promise.all([
          supabase.from('basic_profiles').select('display_name').eq('user_id', user.id).single(),
          supabase.from('basic_profiles').select('display_name').eq('user_id', targetUserId).single(),
        ]);

        // Real-time: both clients listen for 'new_match' so an online user
        // sees the match instantly without reloading the inbox.
        if (matchId) {
          try {
            const { emitToUser } = await import('../socket');
            const matchPayload = {
              matchId,
              status: 'pending_first_message',
              expiresAt: matchExpiresAt,
            };
            emitToUser(user.id, 'new_match', {
              ...matchPayload,
              userId: targetUserId,
              displayName: targetBasic?.display_name || 'Someone',
            });
            emitToUser(targetUserId, 'new_match', {
              ...matchPayload,
              userId: user.id,
              displayName: myBasic?.display_name || 'Someone',
            });
          } catch (err) {
            console.warn('[Actions] new_match socket emit failed:', err);
          }
        }

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
        // Server-authoritative daily counters so clients don't drift or
        // reset on relaunch
        ...(type === 'like'
          ? {
              likes_used_today: likesUsed + 1,
              likes_remaining: Math.max(0, DAILY_LIKE_LIMIT - likesUsed - 1),
            }
          : {}),
        ...(wantsComment
          ? {
              // false only while migration 007 is pending — the like went
              // through but the note was dropped.
              comment_saved: commentSaved,
              comments_used_today: commentsUsed + (commentSaved ? 1 : 0),
              comments_remaining: Math.max(
                0,
                DAILY_COMMENT_LIMIT - commentsUsed - (commentSaved ? 1 : 0),
              ),
            }
          : {}),
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

    // ── Find the last swipe (like OR pass) — Bumble/Hinge-style undo ────────
    // Previously only passes were rewindable, so hitting Undo right after a
    // like resurrected an older passed profile instead.

    type LastAction = {
      id: string;
      target_id: string;
      kind: string;
      created_at: string;
      comment?: string | null;
    };
    const selectLastAction = async (withComment: boolean) =>
      (await supabase
        .from('actions')
        .select(withComment ? 'id, target_id, kind, created_at, comment' : 'id, target_id, kind, created_at')
        .eq('actor_id', user.id)
        .in('kind', ['like', 'pass'])
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle()) as { data: LastAction | null; error: { code?: string; message?: string } | null };

    let { data: lastAction, error: lastActionError } = await selectLastAction(
      !commentColumnKnownMissing(),
    );
    if (lastActionError && isMissingCommentColumnError(lastActionError)) {
      markCommentColumnMissing();
      ({ data: lastAction } = await selectLastAction(false));
    }

    if (!lastAction) {
      throw new AppError(404, 'No recent swipe to rewind', 'NO_PASS_TO_REWIND');
    }

    // A like that already became a mutual match cannot be undone — unmatch is
    // the explicit path for that.
    if (lastAction.kind === 'like') {
      const [userA, userB] = user.id < lastAction.target_id
        ? [user.id, lastAction.target_id]
        : [lastAction.target_id, user.id];
      const { data: existingMatch } = await supabase
        .from('matches')
        .select('id, status')
        .eq('user_a_id', userA)
        .eq('user_b_id', userB)
        .not('status', 'in', '(dissolved,expired,unmatched)')
        .limit(1)
        .maybeSingle();

      if (existingMatch) {
        throw new AppError(
          400,
          "It's already a match! Unmatch from the chat if you've changed your mind.",
          'CANNOT_REWIND_MATCHED',
        );
      }
    }

    // ── Delete the swipe record ─────────────────────────────────────────────

    const { error: deleteError } = await supabase
      .from('actions')
      .delete()
      .eq('id', lastAction.id);

    if (deleteError) {
      throw new AppError(500, 'Failed to rewind swipe', 'REWIND_FAILED');
    }

    // Track the rewind in daily counters
    await incrementDailyCount(user.id, 'rewind');

    // Undoing a like refunds it against the daily like limit (and the daily
    // comment limit if the like carried a comment)
    if (lastAction.kind === 'like') {
      try {
        const likeKey = `daily_like:${user.id}:${todayKey()}`;
        const current = await redis.get(likeKey);
        if (current && parseInt(current, 10) > 0) {
          await redis.decr(likeKey);
        }
        if ((lastAction as { comment?: string | null }).comment) {
          const commentKey = `daily_comment:${user.id}:${todayKey()}`;
          const usedComments = await redis.get(commentKey);
          if (usedComments && parseInt(usedComments, 10) > 0) {
            await redis.decr(commentKey);
          }
        }
      } catch {
        // Redis down — DB fallback recounts naturally since the row is gone
      }
    }

    // Invalidate feed cache so the rewound profile reappears
    await invalidateFeedCache(user.id);

    const rewindsRemaining = DAILY_REWIND_LIMIT - rewindsUsed - 1;

    res.json({
      success: true,
      data: {
        rewound_target_id: lastAction.target_id,
        rewound_kind: lastAction.kind,
        rewinds_remaining: rewindsRemaining,
        rewinds_used_today: rewindsUsed + 1,
      },
    });
  }),
);

// ─── GET /v1/action/prompt ──────────────────────────────────────────────────────
// Today's daily question + the caller's current answer. Prefers the
// cron/admin-scheduled prompt (daily_prompts.date/is_active, migration 008);
// until that lands it falls back to a deterministic rotation through the
// seeded question pool so the feature works either way.

router.get(
  '/prompt',
  authenticate,
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const today = todayKey();

    let question: string | null = null;

    const { data: scheduled, error: scheduledError } = await supabase
      .from('daily_prompts')
      .select('question')
      .eq('date', today)
      .eq('is_active', true)
      .limit(1)
      .maybeSingle();

    if (!scheduledError && scheduled?.question) {
      question = scheduled.question;
    } else {
      const { data: all } = await supabase
        .from('daily_prompts')
        .select('question')
        .order('created_at', { ascending: true });
      if (all && all.length > 0) {
        const dayNumber = Math.floor(Date.now() / 86_400_000);
        question = all[dayNumber % all.length].question;
      }
    }

    const { data: me } = await supabase
      .from('users')
      .select('daily_prompt_answer, daily_prompt_answered_at')
      .eq('id', user.id)
      .single();

    const answeredAt = me?.daily_prompt_answered_at || null;

    res.json({
      success: true,
      data: {
        question,
        answer: me?.daily_prompt_answer || null,
        answered_at: answeredAt,
        answered_today: !!answeredAt && String(answeredAt).slice(0, 10) === today,
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

    // Get all likes targeting current user (incl. like-with-comment notes)
    type IncomingLike = {
      id: string;
      actor_id: string;
      created_at: string;
      comment?: string | null;
    };
    const selectIncomingLikes = async (withComment: boolean) =>
      (await supabase
        .from('actions')
        .select(withComment ? 'id, actor_id, created_at, comment' : 'id, actor_id, created_at')
        .eq('target_id', user.id)
        .eq('kind', 'like')
        .order('created_at', { ascending: false })) as {
        data: IncomingLike[] | null;
        error: { code?: string; message?: string } | null;
      };

    let { data: incomingLikes, error: incomingError } = await selectIncomingLikes(
      !commentColumnKnownMissing(),
    );
    if (incomingError && isMissingCommentColumnError(incomingError)) {
      markCommentColumnMissing();
      ({ data: incomingLikes } = await selectIncomingLikes(false));
    }

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
        { data: likerNameSettings },
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
        supabase
          .from('user_settings')
          .select('user_id, show_full_name')
          .in('user_id', likerIds),
      ]);

      const likerHideFullName = new Set<string>();
      (likerNameSettings || []).forEach((s: any) => {
        if (s.show_full_name === false) likerHideFullName.add(s.user_id);
      });

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

        const likerFirstName = profile.display_name?.split(' ')[0] || 'Unknown';

        likedYouCards.push({
          id: like.actor_id,
          action_id: like.id,
          first_name: likerFirstName,
          display_name: likerHideFullName.has(like.actor_id)
            ? likerFirstName
            : (profile.display_name || 'Unknown'),
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
          like_label: like.comment ? 'Commented on your profile' : 'Liked your profile',
          like_comment: like.comment || null,
          daily_prompt_answer: userMeta?.daily_prompt_answer || null,
          liked_at: like.created_at,
        });
      }

      // Hinge-style: likes that carry a comment float to the top (each group
      // stays newest-first from the query order).
      likedYouCards.sort((a, b) => {
        const aHas = a.like_comment ? 1 : 0;
        const bHas = b.like_comment ? 1 : 0;
        return bHas - aHas;
      });
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
        { data: matchNameSettings },
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
        supabase
          .from('user_settings')
          .select('user_id, show_full_name')
          .in('user_id', otherIds),
      ]);

      const matchHideFullName = new Set<string>();
      (matchNameSettings || []).forEach((s: any) => {
        if (s.show_full_name === false) matchHideFullName.add(s.user_id);
      });

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

        const matchFirstName = profile?.display_name?.split(' ')[0] || 'Unknown';

        matchItems.push({
          match_id: match.id,
          user_id: otherId,
          first_name: matchFirstName,
          display_name: matchHideFullName.has(otherId)
            ? matchFirstName
            : (profile?.display_name || 'Unknown'),
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
          extended_once: match.extended_once || false,
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
