import { Router, Request, Response } from 'express';
import multer from 'multer';
import sharp from 'sharp';
import { v4 as uuidv4 } from 'uuid';
import { supabase } from '../config/supabase';
import { redis } from '../config/redis';
import { AppError, asyncHandler } from '../utils/errors';
import { authenticate } from '../middleware/auth';
import { rateLimit } from '../middleware/rateLimit';
import { AuthenticatedRequest, Icebreaker } from '../types';
import icebreakers from '../data/icebreakers.json';

const router = Router();

/**
 * Broadcast a freshly-inserted message over the socket so the recipient's
 * open chat updates in real time. REST-sent messages (all iOS sends plus
 * Android's fallback and all media uploads) were previously invisible until
 * the recipient manually reloaded the conversation.
 */
async function broadcastNewMessage(
  matchId: string,
  senderId: string,
  otherId: string,
  message: any,
): Promise<void> {
  try {
    const { getSocketServer } = await import('../socket');
    const io = getSocketServer();
    if (!io) return;

    const payload = {
      id: message.id,
      matchId,
      senderId,
      content: message.content ?? null,
      mediaUrl: message.media_url ?? null,
      msgType: message.msg_type,
      isRead: false,
      createdAt: message.sent_at || message.created_at,
    };
    io.to(`user:${otherId}`).emit('new_msg', payload);
    io.to(`match:${matchId}`).emit('new_msg', payload);
  } catch (err) {
    console.warn('[Chat] Socket broadcast failed for REST message:', err);
  }
}

// ─── Multer config for chat media ────────────────────────────────────────────

const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 15 * 1024 * 1024, // 15 MB for chat media
    files: 1,
  },
  fileFilter: (_req, file, cb) => {
    const allowed = [
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/gif',
    ];
    if (allowed.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(
        new AppError(400, 'Unsupported media type. Only JPEG, PNG, WebP, and GIF are allowed.', 'INVALID_MEDIA_TYPE')
      );
    }
  },
});

// ─── Multer config for voice clips (audio) ──────────────────────────────────

const audioUpload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 15 * 1024 * 1024, // 15 MB matches images; ~5 min of compressed audio
    files: 1,
  },
  fileFilter: (_req, file, cb) => {
    const allowed = [
      'audio/m4a',
      'audio/mp4',
      'audio/x-m4a',
      'audio/aac',
      'audio/mpeg',
      'audio/webm',
      'audio/ogg',
      'audio/wav',
    ];
    if (allowed.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(
        new AppError(
          400,
          'Unsupported audio type. Use m4a, aac, mp3, webm, ogg, or wav.',
          'INVALID_AUDIO_TYPE'
        )
      );
    }
  },
});

// ─── Sightengine config ──────────────────────────────────────────────────────

const SIGHTENGINE_API_USER = process.env.SIGHTENGINE_API_USER;
const SIGHTENGINE_API_SECRET = process.env.SIGHTENGINE_API_SECRET;

interface SightengineResult {
  status: string;
  nudity?: { raw: number; partial: number };
  weapon?: number;
  alcohol?: number;
  drugs?: number;
  offensive?: { prob: number };
  gore?: { prob: number };
}

/**
 * Screen an image buffer through Sightengine for NSFW/unsafe content.
 * Uses the base64-upload approach to avoid external form-data dependencies.
 * Returns true if the image is safe, false if rejected.
 * If Sightengine is not configured, logs a warning and allows the image.
 */
async function screenImage(buffer: Buffer): Promise<{ safe: boolean; reason?: string }> {
  if (!SIGHTENGINE_API_USER || !SIGHTENGINE_API_SECRET) {
    console.warn('[Chat] Sightengine not configured, skipping image screening');
    return { safe: true };
  }

  try {
    const base64Image = buffer.toString('base64');
    const dataUri = `data:image/jpeg;base64,${base64Image}`;

    const params = new URLSearchParams({
      media: dataUri,
      models: 'nudity-2.1,offensive,gore',
      api_user: SIGHTENGINE_API_USER,
      api_secret: SIGHTENGINE_API_SECRET,
    });

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10000);

    const response = await fetch('https://api.sightengine.com/1.0/check.json', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: params.toString(),
      signal: controller.signal,
    });

    clearTimeout(timeout);

    if (!response.ok) {
      console.error(`[Chat] Sightengine returned HTTP ${response.status}`);
      return { safe: true }; // Fail open on API error
    }

    const result = (await response.json()) as SightengineResult;

    // Reject if nudity probability is high
    if (result.nudity && (result.nudity.raw > 0.5 || result.nudity.partial > 0.7)) {
      return { safe: false, reason: 'Image contains nudity or sexually explicit content' };
    }

    // Reject if offensive content probability is high
    if (result.offensive && result.offensive.prob > 0.7) {
      return { safe: false, reason: 'Image contains offensive content' };
    }

    // Reject if gore/violence probability is high
    if (result.gore && result.gore.prob > 0.7) {
      return { safe: false, reason: 'Image contains violent or graphic content' };
    }

    return { safe: true };
  } catch (err) {
    console.error('[Chat] Sightengine screening failed:', err);
    // On screening failure, allow the image but log for manual review
    return { safe: true };
  }
}

// ─── Helper: Verify match access ────────────────────────────────────────────

async function verifyMatchAccess(
  matchId: string,
  userId: string
): Promise<{ match: any; otherId: string }> {
  const { data: match, error } = await supabase
    .from('matches')
    .select('*')
    .eq('id', matchId)
    .single();

  if (error || !match) {
    throw new AppError(404, 'Match not found', 'MATCH_NOT_FOUND');
  }

  if (match.user_a_id !== userId && match.user_b_id !== userId) {
    throw new AppError(403, 'Not authorized to access this conversation', 'MATCH_UNAUTHORIZED');
  }

  const otherId =
    match.user_a_id === userId ? match.user_b_id : match.user_a_id;

  return { match, otherId };
}

// ─── Helper: Get random icebreakers ─────────────────────────────────────────

function getRandomIcebreakers(count: number = 3): Icebreaker[] {
  const allIcebreakers = icebreakers as Icebreaker[];
  const shuffled = [...allIcebreakers].sort(() => Math.random() - 0.5);

  // Try to include at least 1 Sindhi and 1 general
  const sindhi = shuffled.filter((i) => i.category === 'sindhi');
  const general = shuffled.filter((i) => i.category === 'general');

  const selected: Icebreaker[] = [];
  if (sindhi.length > 0) selected.push(sindhi[0]);
  if (general.length > 0) selected.push(general[0]);

  // Fill remaining slots
  const remaining = shuffled.filter((i) => !selected.includes(i));
  while (selected.length < count && remaining.length > 0) {
    selected.push(remaining.shift()!);
  }

  return selected;
}

// ─── Helper: Compute countdown remaining ─────────────────────────────────────

function computeCountdown(expiresAt: string | null): number | null {
  if (!expiresAt) return null;
  const remaining = new Date(expiresAt).getTime() - Date.now();
  return remaining > 0 ? Math.ceil(remaining / 1000) : 0;
}

// ─── GET /v1/chat/:matchId ──────────────────────────────────────────────────

router.get(
  '/:matchId',
  authenticate,
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const { matchId } = req.params;
    const before = req.query.before as string | undefined;
    const limit = Math.min(parseInt(req.query.limit as string) || 30, 100);

    const { match, otherId } = await verifyMatchAccess(matchId, user.id);

    // Build message query with cursor pagination (before=msgId)
    let query = supabase
      .from('messages')
      .select('*')
      .eq('match_id', matchId)
      .order('created_at', { ascending: false })
      .limit(limit);

    if (before) {
      // Fetch the timestamp of the cursor message for pagination
      const { data: cursorMsg } = await supabase
        .from('messages')
        .select('created_at')
        .eq('id', before)
        .single();

      if (cursorMsg) {
        query = query.lt('created_at', cursorMsg.created_at);
      } else {
        throw new AppError(400, 'Invalid cursor message ID', 'INVALID_CURSOR');
      }
    }

    const { data: messages, error: msgError } = await query;

    if (msgError) {
      throw new AppError(500, 'Failed to fetch messages', 'MESSAGES_FETCH_FAILED');
    }

    // Mark unread messages from other user as read (with timestamp)
    await supabase
      .from('messages')
      .update({ is_read: true, read_at: new Date().toISOString() })
      .eq('match_id', matchId)
      .eq('sender_id', otherId)
      .eq('is_read', false);

    // Get other user's profile for the chat header
    const [{ data: otherBasic }, { data: otherPhoto }, { data: otherUser }] =
      await Promise.all([
        supabase
          .from('basic_profiles')
          .select('display_name, city, country')
          .eq('user_id', otherId)
          .single(),
        supabase
          .from('photos')
          .select('url_thumb')
          .eq('user_id', otherId)
          .eq('is_primary', true)
          .limit(1)
          .maybeSingle(),
        supabase
          .from('users')
          .select('is_verified, last_active')
          .eq('id', otherId)
          .single(),
      ]);

    // Get icebreakers if no messages exist and not paginating
    const hasMessages = messages && messages.length > 0;
    const suggestedIcebreakers = hasMessages || before ? [] : getRandomIcebreakers(3);

    // Get cultural score for this match
    let culturalScore = match.cultural_score;
    if (culturalScore === null) {
      try {
        const { getCulturalScore } = await import('../services/scoring');
        const cs = await getCulturalScore(user.id, otherId);
        culturalScore = cs.total;
      } catch {
        culturalScore = null;
      }
    }

    // Attach reactions (stored per-message in Redis as { userId: emoji }).
    // The client shows a single reaction chip per message, so surface the
    // reaction placed by the OTHER participant (falling back to any). Without
    // this the POST-stored reactions were never loaded back — they vanished on
    // reload and never reached the other person. Best-effort: Redis down → none.
    const reactionByMsg: Record<string, string> = {};
    try {
      const ids = (messages || []).map((m: any) => m.id);
      if (ids.length) {
        const pipe = redis.pipeline();
        ids.forEach((id: string) => pipe.hgetall(`reactions:${id}`));
        const results = await pipe.exec();
        (messages || []).forEach((m: any, i: number) => {
          const hash = (results?.[i]?.[1] || {}) as Record<string, string>;
          const entries = Object.entries(hash);
          if (!entries.length) return;
          const chosen = entries.find(([uid]) => uid !== m.sender_id) || entries[0];
          reactionByMsg[m.id] = chosen[1];
        });
      }
    } catch {
      // reactions are best-effort; a Redis hiccup must not break chat history
    }

    // Format messages (reverse to chronological order for display)
    const formattedMessages = (messages || []).reverse().map((m: any) => ({
      id: m.id,
      senderId: m.sender_id,
      isYou: m.sender_id === user.id,
      content: m.content,
      msgType: m.msg_type || 'text',
      mediaUrl: m.media_url,
      mediaType: m.media_type,
      isRead: m.is_read,
      readAt: m.read_at || null,
      reaction: reactionByMsg[m.id] || null,
      createdAt: m.created_at,
    }));

    // Determine the oldest message ID for the next "before" cursor
    const oldestMessage = messages?.[messages.length - 1];

    res.json({
      success: true,
      data: {
        matchId,
        matchMeta: {
          matchedAt: match.matched_at,
          firstMsgBy: match.first_msg_by || null,
          // Whether *this* caller sent the first message. Clients use this for
          // the Respect-First lock instead of comparing first_msg_by to their
          // own id (which they don't always have on hand).
          firstMsgByMe: match.first_msg_by != null && match.first_msg_by === user.id,
          firstMsgLocked: match.first_msg_locked ?? false,
          isDissolved: match.is_dissolved ?? (match.status === 'dissolved'),
          expiresAt: match.expires_at || null,
          countdownRemaining: computeCountdown(match.expires_at),
          extendedOnce: match.extended_once ?? false,
        },
        culturalScore,
        otherUser: {
          id: otherId,
          displayName: otherBasic?.display_name || 'Unknown',
          city: otherBasic?.city,
          country: otherBasic?.country,
          photo: otherPhoto?.url_thumb || null,
          isVerified: otherUser?.is_verified || false,
          lastActiveAt: otherUser?.last_active || null,
        },
        messages: formattedMessages,
        icebreakers: suggestedIcebreakers,
        cursor: oldestMessage?.id || null,
        hasMore: (messages?.length || 0) >= limit,
      },
    });
  })
);

// ─── POST /v1/chat/:matchId/media ───────────────────────────────────────────

router.post(
  '/:matchId/media',
  authenticate,
  rateLimit({ maxRequests: 30, windowSeconds: 60, keyPrefix: 'rl_chat_media' }),
  upload.single('media'),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const { matchId } = req.params;
    const file = req.file;

    if (!file) {
      throw new AppError(400, 'No media file uploaded', 'NO_FILE');
    }

    const { match, otherId } = await verifyMatchAccess(matchId, user.id);

    // Reject if match is dissolved
    if (match.is_dissolved || match.status === 'dissolved') {
      throw new AppError(403, 'This match has been dissolved', 'MATCH_DISSOLVED');
    }

    // Reject if match has expired
    if (match.expires_at && new Date(match.expires_at) < new Date()) {
      throw new AppError(403, 'This match has expired', 'MATCH_EXPIRED');
    }

    const mediaId = uuidv4();
    const basePath = `chat/${matchId}/${mediaId}`;
    let processedBuffer = file.buffer;
    let contentType = file.mimetype;

    // Process images with sharp (skip GIFs to preserve animation)
    if (file.mimetype.startsWith('image/') && file.mimetype !== 'image/gif') {
      processedBuffer = await sharp(file.buffer)
        .resize(1200, 1200, { fit: 'inside', withoutEnlargement: true })
        .jpeg({ quality: 80 })
        .toBuffer();
      contentType = 'image/jpeg';
    }

    // Screen image through Sightengine before delivery
    const screenResult = await screenImage(processedBuffer);
    if (!screenResult.safe) {
      throw new AppError(
        400,
        screenResult.reason || 'Image rejected by content moderation',
        'CONTENT_REJECTED'
      );
    }

    // Determine file extension
    const extMap: Record<string, string> = {
      'image/jpeg': 'jpg',
      'image/png': 'png',
      'image/webp': 'webp',
      'image/gif': 'gif',
    };
    const ext = extMap[contentType] || extMap[file.mimetype] || 'jpg';

    // Upload to Supabase Storage
    const { error: uploadError } = await supabase.storage
      .from('chat-media')
      .upload(`${basePath}.${ext}`, processedBuffer, {
        contentType,
        upsert: true,
      });

    if (uploadError) {
      throw new AppError(500, 'Failed to upload media', 'UPLOAD_FAILED');
    }

    const { data: urlData } = supabase.storage
      .from('chat-media')
      .getPublicUrl(`${basePath}.${ext}`);

    // Create message record with msg_type='photo'
    const caption = req.body?.caption || null;

    const { data: message, error: msgError } = await supabase
      .from('messages')
      .insert({
        match_id: matchId,
        sender_id: user.id,
        content: caption,
        msg_type: 'photo',
        media_url: urlData.publicUrl,
        media_type: 'image',
        is_read: false,
      })
      .select()
      .single();

    if (msgError) {
      throw new AppError(500, 'Failed to save message', 'MESSAGE_SAVE_FAILED');
    }

    await broadcastNewMessage(matchId, user.id, otherId, message);

    // Send notification to the other user if they are not in the chat
    try {
      const otherInChat = await redis.get(`in_chat:${otherId}:${matchId}`);
      if (!otherInChat) {
        const { sendTemplateNotification } = await import('../services/notifications');
        const { data: myBasic } = await supabase
          .from('basic_profiles')
          .select('display_name')
          .eq('user_id', user.id)
          .single();

        await sendTemplateNotification('photo_received', otherId, {
          name: myBasic?.display_name || 'Someone',
          matchId, // needed for the notification deep link into the chat
        });
      }
    } catch {
      // Notification failure is non-critical
    }

    res.status(201).json({
      success: true,
      data: {
        messageId: message.id,
        msgType: 'photo',
        mediaUrl: urlData.publicUrl,
        mediaType: 'image',
        createdAt: message.created_at,
      },
    });
  })
);

// ─── POST /v1/chat/:matchId/audio ───────────────────────────────────────────
// Upload a voice message. Stores audio in Supabase Storage chat-media bucket
// and inserts a message row with msg_type='voice', media_url, and the duration
// in seconds (passed as form field 'duration').

router.post(
  '/:matchId/audio',
  authenticate,
  rateLimit({ maxRequests: 30, windowSeconds: 60, keyPrefix: 'rl_chat_audio' }),
  audioUpload.single('audio'),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const { matchId } = req.params;
    const file = req.file;

    if (!file) {
      throw new AppError(400, 'No audio file uploaded', 'NO_FILE');
    }

    const { match, otherId } = await verifyMatchAccess(matchId, user.id);

    if (match.is_dissolved || match.status === 'dissolved') {
      throw new AppError(403, 'This match has been dissolved', 'MATCH_DISSOLVED');
    }
    if (match.expires_at && new Date(match.expires_at) < new Date()) {
      throw new AppError(403, 'This match has expired', 'MATCH_EXPIRED');
    }

    // Parse duration (seconds, integer-ish). Treat malformed values as 0.
    const rawDuration = req.body?.duration;
    let durationSeconds = 0;
    if (rawDuration != null) {
      const parsed = Number(rawDuration);
      if (Number.isFinite(parsed) && parsed >= 0) {
        durationSeconds = Math.min(Math.round(parsed), 300); // cap at 5 min
      }
    }

    const extMap: Record<string, string> = {
      'audio/m4a': 'm4a',
      'audio/mp4': 'm4a',
      'audio/x-m4a': 'm4a',
      'audio/aac': 'aac',
      'audio/mpeg': 'mp3',
      'audio/webm': 'webm',
      'audio/ogg': 'ogg',
      'audio/wav': 'wav',
    };
    const ext = extMap[file.mimetype] || 'm4a';

    const mediaId = uuidv4();
    const path = `chat/${matchId}/${mediaId}.${ext}`;

    const { error: uploadError } = await supabase.storage
      .from('chat-media')
      .upload(path, file.buffer, {
        contentType: file.mimetype,
        upsert: true,
      });

    if (uploadError) {
      throw new AppError(500, 'Failed to upload audio', 'UPLOAD_FAILED');
    }

    const { data: urlData } = supabase.storage
      .from('chat-media')
      .getPublicUrl(path);

    const { data: message, error: msgError } = await supabase
      .from('messages')
      .insert({
        match_id: matchId,
        sender_id: user.id,
        content: durationSeconds > 0 ? `${durationSeconds}` : null,
        msg_type: 'voice',
        media_url: urlData.publicUrl,
        media_type: 'audio',
        is_read: false,
      })
      .select()
      .single();

    if (msgError) {
      throw new AppError(500, 'Failed to save voice message', 'MESSAGE_SAVE_FAILED');
    }

    await broadcastNewMessage(matchId, user.id, otherId, message);

    // Best-effort push notification
    try {
      const otherInChat = await redis.get(`in_chat:${otherId}:${matchId}`);
      if (!otherInChat) {
        const { sendTemplateNotification } = await import('../services/notifications');
        const { data: myBasic } = await supabase
          .from('basic_profiles')
          .select('display_name')
          .eq('user_id', user.id)
          .single();

        await sendTemplateNotification('new_message', otherId, {
          name: myBasic?.display_name || 'Someone',
          matchId,
        });
      }
    } catch {
      // non-critical
    }

    res.status(201).json({
      success: true,
      data: {
        messageId: message.id,
        msgType: 'voice',
        mediaUrl: urlData.publicUrl,
        mediaType: 'audio',
        durationSeconds,
        createdAt: message.created_at,
      },
    });
  })
);

// ─── POST /v1/chat/:matchId/messages ────────────────────────────────────────
// Send a text message via REST API (iOS uses this alongside Socket.io).
// Enforces Respect-First: first sender must wait for reply before sending again.

router.post(
  '/:matchId/messages',
  authenticate,
  rateLimit({ maxRequests: 60, windowSeconds: 60, keyPrefix: 'rl_chat_msg' }),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const { matchId } = req.params;
    // Accept both `type` and `msgType` — the socket path and the Android
    // REST fallback historically used `msgType`.
    const { content, mediaUrl } = req.body;
    const msgType = req.body.type || req.body.msgType || 'text';

    if (!content && !mediaUrl) {
      throw new AppError(400, 'Message content or media URL is required', 'EMPTY_MESSAGE');
    }

    const validTypes = ['text', 'photo', 'voice', 'gif', 'icebreaker'];
    if (!validTypes.includes(msgType)) {
      throw new AppError(400, `Invalid message type: ${msgType}`, 'INVALID_MSG_TYPE');
    }

    const { match, otherId } = await verifyMatchAccess(matchId, user.id);

    // Check dissolved/expired
    if (match.is_dissolved || match.status === 'dissolved') {
      throw new AppError(403, 'This match has been dissolved', 'MATCH_DISSOLVED');
    }

    if (match.status === 'expired') {
      throw new AppError(403, 'This match has expired', 'MATCH_EXPIRED');
    }

    if (match.expires_at && new Date(match.expires_at) < new Date()) {
      // Mark as expired
      await supabase.from('matches').update({ status: 'expired', is_dissolved: true, dissolved_reason: 'expired' }).eq('id', matchId);
      throw new AppError(403, 'This match has expired', 'MATCH_EXPIRED');
    }

    // ── Respect-First enforcement ──
    // If no first message yet, this is the first message
    if (!match.first_msg_by) {
      // Atomic update: set first_msg_by only if still null (race condition safety)
      const { data: updated, error: firstMsgError } = await supabase
        .from('matches')
        .update({
          first_msg_by: user.id,
          first_msg_at: new Date().toISOString(),
          first_msg_locked: true,
          status: 'pending_first_message',
        })
        .eq('id', matchId)
        .is('first_msg_by', null)
        .select()
        .single();

      if (firstMsgError || !updated) {
        // Someone else beat us — re-check
        const { data: recheck } = await supabase.from('matches').select('first_msg_by, first_msg_locked').eq('id', matchId).single();
        if (recheck?.first_msg_by === user.id && recheck?.first_msg_locked) {
          throw new AppError(403, 'Please wait for the other person to reply before sending another message', 'RESPECT_FIRST_LOCKED');
        }
      }
    } else if (match.first_msg_by === user.id && match.first_msg_locked) {
      // I sent first and they haven't replied yet — cannot send more
      throw new AppError(403, 'Please wait for the other person to reply before sending another message', 'RESPECT_FIRST_LOCKED');
    } else if (match.first_msg_by !== user.id && match.first_msg_locked) {
      // Other person sent first, I'm replying — unlock the match!
      await supabase
        .from('matches')
        .update({
          first_msg_locked: false,
          status: 'active',
          expires_at: null, // Clear timer once both have messaged
        })
        .eq('id', matchId);

      // Real-time: tell both users the match is now active (unlock banners,
      // countdown removal) without waiting for a reload.
      try {
        const { emitToUser } = await import('../socket');
        const update = { matchId, status: 'active', firstMsgLocked: false, expiresAt: null };
        emitToUser(user.id, 'match_update', update);
        emitToUser(otherId, 'match_update', update);
      } catch {
        // Non-critical
      }
    }

    // ── AI moderation for any text content (icebreakers included) ──
    if (content) {
      try {
        const { screenMessage, checkEarlyMessageContactSharing } = await import('../services/moderation');

        // Check contact sharing in first 5 messages
        const { count: msgCount } = await supabase
          .from('messages')
          .select('*', { count: 'exact', head: true })
          .eq('match_id', matchId);

        if ((msgCount || 0) < 5) {
          const hasContactInfo = await checkEarlyMessageContactSharing(matchId, content);
          if (hasContactInfo) {
            throw new AppError(400, 'Sharing contact information is not allowed in the first few messages', 'CONTACT_SHARING_BLOCKED');
          }
        }

        const textScreen = await screenMessage(content);
        if (!textScreen.pass) {
          throw new AppError(400, 'Message was flagged by content moderation', 'MESSAGE_REJECTED');
        }
      } catch (err) {
        if (err instanceof AppError) throw err;
        // Moderation service failure — allow message
        console.warn('[Chat] Moderation check failed, allowing message:', err);
      }
    }

    // ── Insert message ──
    const messageId = uuidv4();
    const { data: message, error: insertError } = await supabase
      .from('messages')
      .insert({
        id: messageId,
        match_id: matchId,
        sender_id: user.id,
        content: content || null,
        media_url: mediaUrl || null,
        msg_type: msgType,
        sent_at: new Date().toISOString(),
      })
      .select()
      .single();

    if (insertError) {
      throw new AppError(500, 'Failed to send message', 'MESSAGE_SEND_FAILED');
    }

    // Update match last message metadata
    await supabase
      .from('matches')
      .update({
        last_msg_text: content?.substring(0, 100) || `[${msgType}]`,
        last_msg_at: new Date().toISOString(),
        last_msg_by: user.id,
      })
      .eq('id', matchId);

    // NOTE: matches.unread_a/unread_b are intentionally NOT maintained —
    // nothing reads them (inbox unread counts come from messages.read_at) and
    // nothing ever reset them, so the old increment here was two dead DB
    // round-trips per message.

    await broadcastNewMessage(matchId, user.id, otherId, message);

    // Send push notification if other user is not in chat
    try {
      // Key format is in_chat:{userId}:{matchId} (set by enter_chat)
      const inChatKey = `in_chat:${otherId}:${matchId}`;
      const isInChat = await redis.get(inChatKey);

      if (!isInChat) {
        const { checkConversationCooldown } = await import('../services/notifications');
        const canSendPush = await checkConversationCooldown(matchId, otherId);

        if (canSendPush) {
          const { sendTemplateNotification } = await import('../services/notifications');
          const { data: myBasic } = await supabase
            .from('basic_profiles')
            .select('display_name')
            .eq('user_id', user.id)
            .single();

          await sendTemplateNotification('new_message', otherId, {
            name: myBasic?.display_name || 'Someone',
            matchId,
          });
        }
      }
    } catch {
      // Notification failure is non-critical
    }

    res.status(201).json({
      success: true,
      data: {
        message: {
          id: message.id,
          match_id: matchId,
          sender_id: user.id,
          content: message.content,
          media_url: message.media_url,
          msg_type: message.msg_type,
          status: 'sent',
          created_at: message.sent_at,
        },
      },
    });
  })
);

// ─── POST /v1/chat/:matchId/extend ──────────────────────────────────────────

router.post(
  '/:matchId/extend',
  authenticate,
  rateLimit({ maxRequests: 5, windowSeconds: 60, keyPrefix: 'rl_chat_extend' }),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const { matchId } = req.params;

    const { match } = await verifyMatchAccess(matchId, user.id);

    // Check if match is dissolved
    if (match.is_dissolved || match.status === 'dissolved') {
      throw new AppError(403, 'Cannot extend a dissolved match', 'MATCH_DISSOLVED');
    }

    // Check if match has already expired
    if (match.expires_at && new Date(match.expires_at) < new Date()) {
      throw new AppError(403, 'Cannot extend an expired match', 'MATCH_EXPIRED');
    }

    // Check if already extended once
    if (match.extended_once) {
      throw new AppError(
        400,
        'This match has already been extended once. Each match can only be extended once.',
        'ALREADY_EXTENDED'
      );
    }

    // Calculate new expiry: current expires_at + 24 hours
    // If no expires_at is set, extend from now
    const currentExpiry = match.expires_at
      ? new Date(match.expires_at)
      : new Date();
    const newExpiry = new Date(currentExpiry.getTime() + 24 * 60 * 60 * 1000);

    // Update the match
    const { data: updatedMatch, error: updateError } = await supabase
      .from('matches')
      .update({
        expires_at: newExpiry.toISOString(),
        extended_once: true,
      })
      .eq('id', matchId)
      .select()
      .single();

    if (updateError) {
      throw new AppError(500, 'Failed to extend match deadline', 'EXTEND_FAILED');
    }

    // Notify the other user about the extension
    try {
      const otherId =
        match.user_a_id === user.id ? match.user_b_id : match.user_a_id;

      const { sendTemplateNotification } = await import('../services/notifications');
      const { data: myBasic } = await supabase
        .from('basic_profiles')
        .select('display_name')
        .eq('user_id', user.id)
        .single();

      await sendTemplateNotification('match_expiring', otherId, {
        name: myBasic?.display_name || 'Someone',
      });
    } catch {
      // Notification failure is non-critical
    }

    res.json({
      success: true,
      data: {
        matchId,
        expiresAt: newExpiry.toISOString(),
        countdownRemaining: computeCountdown(newExpiry.toISOString()),
        extendedOnce: true,
      },
    });
  })
);

// ─── POST /v1/chat/:matchId/messages/:messageId/reaction ────────────────────
// Add or replace the current user's reaction on a message. Stored in Redis
// (no Supabase schema change). One emoji per user per message.

const ALLOWED_REACTIONS = ['❤️', '😂', '😮', '😢', '😡', '👍'];

router.post(
  '/:matchId/messages/:messageId/reaction',
  authenticate,
  rateLimit({ maxRequests: 60, windowSeconds: 60, keyPrefix: 'rl_chat_react' }),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const { matchId, messageId } = req.params;
    const { emoji } = req.body;

    if (!emoji || typeof emoji !== 'string') {
      throw new AppError(400, 'Emoji is required', 'EMPTY_EMOJI');
    }
    if (!ALLOWED_REACTIONS.includes(emoji)) {
      throw new AppError(400, 'Reaction emoji not allowed', 'INVALID_EMOJI');
    }

    await verifyMatchAccess(matchId, user.id);

    // Confirm the message belongs to this match
    const { data: msg, error: fetchError } = await supabase
      .from('messages')
      .select('id')
      .eq('id', messageId)
      .eq('match_id', matchId)
      .single();
    if (fetchError || !msg) {
      throw new AppError(404, 'Message not found', 'MESSAGE_NOT_FOUND');
    }

    const key = `reactions:${messageId}`;
    await redis.hset(key, user.id, emoji);
    // Reactions live as long as the match — give a generous TTL just to avoid
    // unbounded growth if a match is dissolved without cleanup.
    await redis.expire(key, 60 * 60 * 24 * 30); // 30 days

    const all = await redis.hgetall(key);

    res.status(201).json({
      success: true,
      data: { messageId, reactions: all },
    });
  })
);

router.delete(
  '/:matchId/messages/:messageId/reaction',
  authenticate,
  rateLimit({ maxRequests: 60, windowSeconds: 60, keyPrefix: 'rl_chat_react' }),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const { matchId, messageId } = req.params;

    await verifyMatchAccess(matchId, user.id);

    const key = `reactions:${messageId}`;
    await redis.hdel(key, user.id);
    const all = await redis.hgetall(key);

    res.json({
      success: true,
      data: { messageId, reactions: all },
    });
  })
);

// ─── PATCH /v1/chat/:matchId/messages/:messageId ────────────────────────────
// Edit a text message. Sender-only. Appends "[edited]" marker so clients can
// surface the "edited" tag without needing a new DB column.

router.patch(
  '/:matchId/messages/:messageId',
  authenticate,
  rateLimit({ maxRequests: 30, windowSeconds: 60, keyPrefix: 'rl_chat_edit' }),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const { matchId, messageId } = req.params;
    const { content } = req.body;

    if (!content || typeof content !== 'string' || !content.trim()) {
      throw new AppError(400, 'Message content is required', 'EMPTY_MESSAGE');
    }

    await verifyMatchAccess(matchId, user.id);

    // Fetch message and verify sender
    const { data: existing, error: fetchError } = await supabase
      .from('messages')
      .select('id, sender_id, msg_type, content')
      .eq('id', messageId)
      .eq('match_id', matchId)
      .single();

    if (fetchError || !existing) {
      throw new AppError(404, 'Message not found', 'MESSAGE_NOT_FOUND');
    }
    if (existing.sender_id !== user.id) {
      throw new AppError(403, 'You can only edit your own messages', 'NOT_SENDER');
    }
    if (existing.msg_type !== 'text') {
      throw new AppError(400, 'Only text messages can be edited', 'UNEDITABLE_TYPE');
    }

    const trimmed = content.trim();
    const editedContent = trimmed.includes('[edited]') ? trimmed : `${trimmed} [edited]`;

    const { data: updated, error: updateError } = await supabase
      .from('messages')
      .update({ content: editedContent })
      .eq('id', messageId)
      .select()
      .single();

    if (updateError) {
      throw new AppError(500, 'Failed to edit message', 'MESSAGE_EDIT_FAILED');
    }

    res.json({
      success: true,
      data: {
        message: {
          id: updated.id,
          match_id: matchId,
          sender_id: user.id,
          content: updated.content,
          media_url: updated.media_url,
          msg_type: updated.msg_type,
          edited: true,
          created_at: updated.sent_at,
        },
      },
    });
  })
);

// ─── DELETE /v1/chat/:matchId/messages/:messageId ───────────────────────────
// Delete a message. Sender-only. Hard delete.

router.delete(
  '/:matchId/messages/:messageId',
  authenticate,
  rateLimit({ maxRequests: 30, windowSeconds: 60, keyPrefix: 'rl_chat_delete' }),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const { matchId, messageId } = req.params;

    await verifyMatchAccess(matchId, user.id);

    // Fetch message and verify sender
    const { data: existing, error: fetchError } = await supabase
      .from('messages')
      .select('id, sender_id')
      .eq('id', messageId)
      .eq('match_id', matchId)
      .single();

    if (fetchError || !existing) {
      throw new AppError(404, 'Message not found', 'MESSAGE_NOT_FOUND');
    }
    if (existing.sender_id !== user.id) {
      throw new AppError(403, 'You can only delete your own messages', 'NOT_SENDER');
    }

    const { error: deleteError } = await supabase
      .from('messages')
      .delete()
      .eq('id', messageId);

    if (deleteError) {
      throw new AppError(500, 'Failed to delete message', 'MESSAGE_DELETE_FAILED');
    }

    res.json({
      success: true,
      data: { messageId, deleted: true },
    });
  })
);

// ─── POST /v1/chat/:matchId/unmatch ─────────────────────────────────────────
// Dissolve a match. Either participant can unmatch; irreversible. Idempotent.
router.post(
  '/:matchId/unmatch',
  authenticate,
  rateLimit({ maxRequests: 10, windowSeconds: 60, keyPrefix: 'rl_chat_unmatch' }),
  asyncHandler(async (req: Request, res: Response) => {
    const user = (req as AuthenticatedRequest).user;
    const { matchId } = req.params;

    const { match } = await verifyMatchAccess(matchId, user.id);

    // Already dissolved → treat as success so a retry / double-tap is harmless.
    if (!(match.is_dissolved || match.status === 'dissolved')) {
      const { error: updateError } = await supabase
        .from('matches')
        .update({
          status: 'dissolved',
          is_dissolved: true,
          dissolved_at: new Date().toISOString(),
          dissolved_reason: 'unmatched',
        })
        .eq('id', matchId);

      if (updateError) {
        throw new AppError(500, 'Failed to unmatch', 'UNMATCH_FAILED');
      }
    }

    res.json({ success: true, data: { matchId, dissolved: true } });
  })
);

export default router;
