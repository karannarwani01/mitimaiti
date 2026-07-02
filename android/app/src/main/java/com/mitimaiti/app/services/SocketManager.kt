package com.mitimaiti.app.services

import io.socket.client.IO
import io.socket.client.Socket
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONObject

/**
 * WebSocket manager for real-time chat.
 * Mirrors: backend/src/socket.ts events
 *
 * Events sent:
 *   send_msg     { matchId, content, msgType }
 *   typing       { matchId }
 *   enter_chat   { matchId }
 *   leave_chat   { matchId }
 *   heartbeat    { }
 *
 * Events received:
 *   new_msg      { id, matchId, senderId, content, msgType, createdAt }
 *   typing       { matchId, userId }
 *   msg_read     { matchId, readBy }
 *   match_update { matchId, status, firstMsgLocked, ... }
 *   new_match    { match object }
 *   error        { message }
 */
class SocketManager private constructor() {
    private var socket: Socket? = null
    private var tokenProvider: (suspend () -> String?)? = null

    /** The match whose chat screen is currently open (null = none). Global
     *  listeners use this to avoid double-notifying for the visible chat. */
    @Volatile
    var activeChatMatchId: String? = null

    private val _isConnected = MutableStateFlow(false)
    val isConnected: StateFlow<Boolean> = _isConnected.asStateFlow()

    private val _incomingMessages = MutableSharedFlow<JSONObject>(extraBufferCapacity = 64)
    val incomingMessages: SharedFlow<JSONObject> = _incomingMessages.asSharedFlow()

    private val _typingEvents = MutableSharedFlow<JSONObject>(extraBufferCapacity = 64)
    val typingEvents: SharedFlow<JSONObject> = _typingEvents.asSharedFlow()

    private val _readReceipts = MutableSharedFlow<JSONObject>(extraBufferCapacity = 64)
    val readReceipts: SharedFlow<JSONObject> = _readReceipts.asSharedFlow()

    private val _matchUpdates = MutableSharedFlow<JSONObject>(extraBufferCapacity = 16)
    val matchUpdates: SharedFlow<JSONObject> = _matchUpdates.asSharedFlow()

    private val _newMatches = MutableSharedFlow<JSONObject>(extraBufferCapacity = 16)
    val newMatches: SharedFlow<JSONObject> = _newMatches.asSharedFlow()

    /** Fires on RE-connects (not the initial connect) so open chats can
     *  backfill messages that arrived during the outage. */
    private val _reconnects = MutableSharedFlow<Unit>(extraBufferCapacity = 4)
    val reconnects: SharedFlow<Unit> = _reconnects.asSharedFlow()
    private var wasEverConnected = false

    fun init(getToken: suspend () -> String?) {
        this.tokenProvider = getToken
    }

    fun connect(token: String) {
        if (socket?.connected() == true) return

        val opts = IO.Options().apply {
            auth = mapOf("token" to token)
            transports = arrayOf("websocket", "polling")
            reconnection = true
            reconnectionAttempts = 10
            reconnectionDelay = 1000
            reconnectionDelayMax = 5000
            timeout = 20000
        }

        socket = IO.socket(ApiConfig.SOCKET_URL, opts).apply {
            on(Socket.EVENT_CONNECT) {
                _isConnected.value = true
                emit("heartbeat", JSONObject())
                if (wasEverConnected) _reconnects.tryEmit(Unit)
                wasEverConnected = true
            }

            on(Socket.EVENT_DISCONNECT) {
                _isConnected.value = false
            }

            on("new_msg") { args ->
                if (args.isNotEmpty()) {
                    _incomingMessages.tryEmit(args[0] as JSONObject)
                }
            }

            on("typing") { args ->
                if (args.isNotEmpty()) {
                    _typingEvents.tryEmit(args[0] as JSONObject)
                }
            }

            // Backend emits 'messages_read' (payload { matchId, readBy, readAt })
            on("messages_read") { args ->
                if (args.isNotEmpty()) {
                    _readReceipts.tryEmit(args[0] as JSONObject)
                }
            }

            on("match_update") { args ->
                if (args.isNotEmpty()) {
                    _matchUpdates.tryEmit(args[0] as JSONObject)
                }
            }

            on("new_match") { args ->
                if (args.isNotEmpty()) {
                    _newMatches.tryEmit(args[0] as JSONObject)
                }
            }

            on("error") { args ->
                // Log socket errors
                android.util.Log.e("SocketManager", "Socket error: ${args.firstOrNull()}")
            }

            connect()
        }
    }

    fun disconnect() {
        socket?.disconnect()
        socket = null
        _isConnected.value = false
    }

    // ── Send events ──

    /**
     * Send a message and surface the server ack. The backend rejects messages
     * via the ack (rate limit, moderation block, Respect-First lock) — without
     * reading it, rejected messages would silently look sent.
     */
    fun sendMessage(
        matchId: String,
        content: String,
        msgType: String = "text",
        onResult: ((success: Boolean, error: String?, messageId: String?) -> Unit)? = null
    ) {
        socket?.emit("send_msg", JSONObject().apply {
            put("matchId", matchId)
            put("content", content)
            put("msgType", msgType)
        }, io.socket.client.Ack { args ->
            val ack = args.firstOrNull() as? JSONObject
            val error = ack?.optString("error")?.takeIf { it.isNotBlank() }
            val messageId = ack?.optString("messageId")?.takeIf { it.isNotBlank() }
            onResult?.invoke(error == null, error, messageId)
        })
    }

    fun sendTyping(matchId: String) {
        socket?.emit("typing", JSONObject().apply {
            put("matchId", matchId)
        })
    }

    fun enterChat(matchId: String) {
        socket?.emit("enter_chat", JSONObject().apply {
            put("matchId", matchId)
        })
    }

    fun leaveChat(matchId: String) {
        socket?.emit("leave_chat", JSONObject().apply {
            put("matchId", matchId)
        })
    }

    fun sendHeartbeat() {
        socket?.emit("heartbeat", JSONObject())
    }

    companion object {
        val shared = SocketManager()
    }
}
