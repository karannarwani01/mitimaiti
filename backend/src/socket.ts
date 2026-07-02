import { Server as HttpServer } from 'http';
import { Server, Socket } from 'socket.io';
import { supabase } from './config/supabase';
import { redis } from './config/redis';
import { SocketSendMessage, SocketTypingEvent, SocketEnterChat } from './types';
import { screenMessage, checkEarlyMessageContactSharing } from './services/moderation';
import { sendPush, checkConversationCooldown } from './services/notifications';

// ─── Constants ───────────────────────────────────────────────────────────────

const ONLINE_TTL_SECONDS = 300;     // 5 min presence TTL
const HEARTBEAT_REFRESH = 30;       // 30s heartbeat interval
const TYPING_TTL_SECONDS = 3;       // 3s typing indicator
const IN_CHAT_TTL_SECONDS = 3600;   // 1h in-chat marker

// ─── Socket Server ───────────────────────────────────────────────────────────

let io: Server;

export function createSocketServer(httpServer?: HttpServer): Server {
  io = new Server(httpServer || parseInt(process.env.SOCKET_PORT || '4001', 10), {
    cors: {
      origin: (origin, callback) => {
        // Allow all origins for mobile (they don't send Origin headers)
        if (!origin) return callback(null, true);
        const allowed = process.env.CORS_ORIGINS?.split(',').map(o => o.trim()) || [];
        if (allowed.includes('*') || allowed.includes(origin)) return callback(null, true);
        if (/^(capacitor|ionic|exp|mitimaiti):\/\//.test(origin)) return callback(null, true);
        if (/^https?:\/\/(localhost|127\.0\.0\.1|10\.0\.2\.2)(:\d+)?$/.test(origin)) return callback(null, true);
        callback(null, false);
      },
      methods: ['GET', 'POST'],
    },
    pingInterval: 25000,
    pingTimeout: 20000,
    transports: ['websocket', 'polling'],
  });

  // ─── Authentication Middleware ─────────────────────────────────────────────

  io.use(async (socket: Socket, next) => {
    try {
      const token =
        socket.handshake.auth?.token ||
        socket.handshake.query?.token as string ||
        socket.handshake.headers?.authorization?.replace('Bearer ', '');

      if (!token) {
        return next(new Error('Authentication token required'));
      }

      // Verify Supabase JWT
      const {
        data: { user: authUser },
        error,
      } = await supabase.auth.getUser(token);

      if (error || !authUser) {
        return next(new Error('Invalid or expired token'));
      }

      // Check JWT blacklist
      const blacklisted = await redis.get(`jwt_blacklist:${authUser.id}`);
      if (blacklisted) {
        return next(new Error('Token has been revoked'));
      }

      // Get user from DB
      const { data: dbUser } = await supabase
        .from('users')
        .select('id, auth_id, is_active, is_banned, is_suspended')
        .eq('auth_id', authUser.id)
        .single();

      if (!dbUser || !dbUser.is_active || dbUser.is_banned || dbUser.is_suspended) {
        return next(new Error('Account is not active'));
      }

      // Attach user info to socket
      (socket as any).userId = dbUser.id;
      (socket as any).authId = dbUser.auth_id;

      next();
    } catch (err) {
      next(new Error('Authentication failed'));
    }
  });

  // ─── Connection Handler ───────────────────────────────────────────────────

  io.on('connection', (socket: Socket) => {
    const userId = (socket as any).userId as string;

    console.log(`[Socket] Connected: ${userId} (${socket.id})`);

    // Join personal room
    socket.join(`user:${userId}`);

    // Set online presence in Redis with 5min TTL
    redis.set(`online:${userId}`, '1', 'EX', ONLINE_TTL_SECONDS).catch(() => {});

    // ─── Per-socket rate limiting ─────────────────────────────────────────
    const socketRateLimit = new Map<string, number[]>();
    function checkSocketRate(event: string, maxPerMinute: number): boolean {
      const now = Date.now();
      const windowMs = 60000;
      const timestamps = socketRateLimit.get(event) || [];
      const recent = timestamps.filter(t => now - t < windowMs);
      if (recent.length >= maxPerMinute) return false;
      recent.push(now);
      socketRateLimit.set(event, recent);
      return true;
    }

    // ─── send_msg — THE CORE USP: Respect-First Chat Enforcement ──────────

    socket.on('send_msg', async (data: SocketSendMessage, ack?: Function) => {
      try {
        if (!checkSocketRate('send_msg', 30)) {
          return ack?.({ error: 'Rate limit: too many messages. Slow down.' });
        }

        const { matchId, content, mediaUrl, msgType } = data;

        if (!matchId) {
          return ack?.({ error: 'matchId is required' });
        }

        if (!content && !mediaUrl) {
          return ack?.({ error: 'Message content or media is required' });
        }

        // ─── Step 1: Load the match ─────────────────────────────────────

        const { data: match, error: matchErr } = await supabase
          .from('matches')
          .select('id, user_a_id, user_b_id, status, first_msg_by, first_msg_locked, first_msg_at, dissolved_at')
          .eq('id', matchId)
          .single();

        if (matchErr || !match) {
          return ack?.({ error: 'Match not found' });
        }

        // Verify sender is part of this match
        if (match.user_a_id !== userId && match.user_b_id !== userId) {
          return ack?.({ error: 'Not authorized' });
        }

        // Check match is still live. Matches are created as
        // 'pending_first_message' and only become 'active' after the first
        // reply, so both statuses must be able to send here — requiring
        // 'active' would reject every first message sent over the socket.
        if (
          match.dissolved_at ||
          match.status === 'dissolved' ||
          match.status === 'expired'
        ) {
          return ack?.({ error: 'Match is no longer active' });
        }

        const otherId = match.user_a_id === userId ? match.user_b_id : match.user_a_id;

        // ─── Step 2: First Message Logic (Respect-First) ────────────────

        if (match.first_msg_by === null) {
          // No one has sent the first message yet.
          // Atomic UPDATE — only one sender can claim first message.
          const { data: updateResult, error: updateErr } = await supabase
            .from('matches')
            .update({
              first_msg_by: userId,
              first_msg_locked: true,
              first_msg_at: new Date().toISOString(),
            })
            .eq('id', matchId)
            .is('first_msg_by', null) // Atomic: only if still NULL
            .select('id')
            .maybeSingle();

          if (updateErr || !updateResult) {
            // Someone else claimed first message between our read and write
            return ack?.({ error: 'Someone else sent the first message. Please wait for them.' });
          }

          // Sender IS now the first_msg_by — they can send this message.
          // Fall through to message insertion.
        } else {
          // First message has already been sent.
          // Respect-First rule: After the first message is sent,
          // ONLY THE RECEIVER can reply next. The first-message sender
          // must wait for a reply before sending again.

          if (match.first_msg_locked && match.first_msg_by === userId) {
            // The sender of the first message is trying to send again
            // before the receiver has replied. Check if receiver has replied.
            const { count: replyCount } = await supabase
              .from('messages')
              .select('*', { count: 'exact', head: true })
              .eq('match_id', matchId)
              .eq('sender_id', otherId);

            if (!replyCount || replyCount === 0) {
              return ack?.({
                error: 'Please wait for them to reply to your first message.',
              });
            }

            // Receiver has replied at least once — unlock the conversation.
            // Update the lock so both can chat freely now.
            if (match.first_msg_locked) {
              await supabase
                .from('matches')
                .update({
                  first_msg_locked: false,
                  status: 'active',
                  expires_at: null, // Clear timer once both have messaged
                })
                .eq('id', matchId);
            }
          } else if (match.first_msg_locked && match.first_msg_by !== userId) {
            // The receiver is replying to the first message — this unlocks
            // the conversation and activates the match (same as the REST path).
            await supabase
              .from('matches')
              .update({
                first_msg_locked: false,
                status: 'active',
                expires_at: null, // Clear timer once both have messaged
              })
              .eq('id', matchId);
          }
        }

        // ─── Step 3: AI Moderation ──────────────────────────────────────

        let cleanContent = content || null;

        if (cleanContent) {
          // Check for contact sharing in first 5 messages
          const blocked = await checkEarlyMessageContactSharing(matchId, cleanContent);
          if (blocked) {
            return ack?.({
              error: 'Sharing contact information is not allowed in the first few messages.',
            });
          }

          // AI moderation screen
          const moderationResult = await screenMessage(cleanContent);
          if (!moderationResult.pass) {
            return ack?.({
              error: `Message blocked: ${moderationResult.reason}. Please keep conversations respectful.`,
            });
          }
        }

        // ─── Step 4: Insert Message ─────────────────────────────────────

        const { data: message, error: msgError } = await supabase
          .from('messages')
          .insert({
            match_id: matchId,
            sender_id: userId,
            content: cleanContent,
            media_url: mediaUrl || null,
            msg_type: msgType || 'text',
            is_read: false,
          })
          .select()
          .single();

        if (msgError) {
          console.error('[Socket] Message insert error:', msgError.message);
          return ack?.({ error: 'Failed to save message' });
        }

        // ─── Step 5: Emit to Other User ─────────────────────────────────

        const messagePayload = {
          id: message.id,
          matchId,
          senderId: userId,
          content: cleanContent,
          mediaUrl: message.media_url,
          msgType: message.msg_type,
          isRead: false,
          createdAt: message.created_at,
        };

        // Emit to other user's personal room
        io.to(`user:${otherId}`).emit('new_msg', messagePayload);

        // Also emit to match room if both are in it
        io.to(`match:${matchId}`).emit('new_msg', messagePayload);

        // ─── Step 6: Push Notification ──────────────────────────────────

        const otherInChat = await redis.get(`in_chat:${otherId}:${matchId}`);
        if (!otherInChat) {
          // Check 3-min conversation cooldown before sending push
          const canSendPush = await checkConversationCooldown(matchId, otherId);
          if (canSendPush) {
            const { data: senderBasic } = await supabase
              .from('basic_profiles')
              .select('display_name')
              .eq('user_id', userId)
              .single();

            await sendPush(otherId, 'message_received', {
              name: senderBasic?.display_name || 'Someone',
              matchId,
            });
          }
        }

        ack?.({ success: true, messageId: message.id });
      } catch (err) {
        console.error('[Socket] send_msg error:', err);
        ack?.({ error: 'Failed to send message' });
      }
    });

    // ─── typing — Debounced with 3s Redis TTL ──────────────────────────────

    socket.on('typing', async (data: SocketTypingEvent) => {
      try {
        if (!checkSocketRate('typing', 60)) return;
        const { matchId } = data;

        // Verify match access
        const { data: match } = await supabase
          .from('matches')
          .select('user_a_id, user_b_id')
          .eq('id', matchId)
          .single();

        if (!match) return;
        if (match.user_a_id !== userId && match.user_b_id !== userId) return;

        const otherId = match.user_a_id === userId ? match.user_b_id : match.user_a_id;

        // Set Redis typing indicator with 3s TTL (debounce)
        await redis.set(`typing:${matchId}:${userId}`, '1', 'EX', TYPING_TTL_SECONDS);

        // Emit to other user
        io.to(`user:${otherId}`).emit('typing', {
          matchId,
          userId,
          isTyping: true,
        });
      } catch (err) {
        console.error('[Socket] typing error:', err);
      }
    });

    // ─── enter_chat — Mark messages as read + emit read receipt ─────────────

    socket.on('enter_chat', async (data: SocketEnterChat) => {
      try {
        const { matchId } = data;

        // Join the match room
        socket.join(`match:${matchId}`);

        // Mark user as in this chat (for notification suppression)
        await redis.set(`in_chat:${userId}:${matchId}`, '1', 'EX', IN_CHAT_TTL_SECONDS);

        // Verify match access
        const { data: match } = await supabase
          .from('matches')
          .select('user_a_id, user_b_id')
          .eq('id', matchId)
          .single();

        if (!match) return;
        if (match.user_a_id !== userId && match.user_b_id !== userId) return;

        const otherId = match.user_a_id === userId ? match.user_b_id : match.user_a_id;

        // Mark all unread messages from the other user as read (with timestamp)
        const readAt = new Date().toISOString();
        await supabase
          .from('messages')
          .update({ is_read: true, read_at: readAt })
          .eq('match_id', matchId)
          .eq('sender_id', otherId)
          .eq('is_read', false);

        // Emit read receipt to other user with timestamp.
        // 'msg_read' is a legacy alias — clients installed before the event
        // rename still listen for it.
        const readPayload = { matchId, readBy: userId, readAt };
        io.to(`user:${otherId}`).emit('messages_read', readPayload);
        io.to(`user:${otherId}`).emit('msg_read', readPayload);
      } catch (err) {
        console.error('[Socket] enter_chat error:', err);
      }
    });

    // ─── leave_chat ────────────────────────────────────────────────────────

    socket.on('leave_chat', async (data: { matchId: string }) => {
      try {
        const { matchId } = data;
        socket.leave(`match:${matchId}`);
        await redis.del(`in_chat:${userId}:${matchId}`);
      } catch (err) {
        console.error('[Socket] leave_chat error:', err);
      }
    });

    // ─── heartbeat — Refresh online presence every 30s ─────────────────────

    socket.on('heartbeat', async () => {
      try {
        await redis.set(`online:${userId}`, '1', 'EX', ONLINE_TTL_SECONDS);
      } catch {
        // Non-critical — silently fail
      }
    });

    // ─── disconnect ────────────────────────────────────────────────────────

    socket.on('disconnect', async (reason) => {
      console.log(`[Socket] Disconnected: ${userId} (${socket.id}) - ${reason}`);

      // Remove online presence
      await redis.del(`online:${userId}`).catch(() => {});

      // Clean up in-chat markers
      let cursor = '0';
      do {
        const [newCursor, keys] = await redis.scan(
          cursor,
          'MATCH',
          `in_chat:${userId}:*`,
          'COUNT',
          100
        );
        cursor = newCursor;
        if (keys.length > 0) {
          await redis.del(...keys);
        }
      } while (cursor !== '0');
    });
  });

  console.log('[Socket] Server initialized');

  return io;
}

// ─── Utility Exports ─────────────────────────────────────────────────────────

/**
 * Get the Socket.io server instance.
 */
export function getSocketServer(): Server | null {
  return io || null;
}

/**
 * Emit an event to a specific user.
 */
export function emitToUser(userId: string, event: string, data: any): void {
  if (io) {
    io.to(`user:${userId}`).emit(event, data);
  }
}

export default { createSocketServer, getSocketServer, emitToUser };
