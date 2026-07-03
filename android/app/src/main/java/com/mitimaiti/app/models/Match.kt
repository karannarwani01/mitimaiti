package com.mitimaiti.app.models

import java.util.UUID

data class Message(
    val id: String = UUID.randomUUID().toString(),
    val matchId: String = "",
    val senderId: String = "",
    val content: String = "",
    val mediaUrl: String? = null,
    val msgType: MessageType = MessageType.TEXT,
    val status: MessageStatus = MessageStatus.SENT,
    val createdAt: Long = System.currentTimeMillis(),
    val reaction: String? = null,
    val durationSeconds: Int = 0
) {
    companion object {
        val ALLOWED_REACTIONS = listOf("❤️", "😂", "😮", "😢", "😡", "👍")

        /** The logged-in user's real id, set at login/session restore. Messages
         *  fetched from the backend carry real UUIDs — comparing only against
         *  the optimistic "current-user-id" marker rendered every server-loaded
         *  message (including your own) on the other person's side. */
        @Volatile
        var currentUserId: String? = null
    }

    val isFromMe: Boolean
        get() = senderId == "current-user-id" ||
            (currentUserId != null && senderId == currentUserId)
}

data class Match(
    val id: String = UUID.randomUUID().toString(),
    val otherUser: User,
    val status: MatchStatus = MatchStatus.PENDING_FIRST_MESSAGE,
    val matchedAt: Long = System.currentTimeMillis(),
    val expiresAt: Long? = null,
    val lastMessage: String? = null,
    val unreadCount: Int = 0,
    val firstMsgBy: String? = null,
    /** Server-computed: whether the current user sent the first message. Used
     *  for the Respect-First lock so we don't compare ids client-side. */
    val firstMsgByMe: Boolean = false,
    val firstMsgLocked: Boolean = false,
    val firstMsgAt: Long? = null
) {
    val isExpired: Boolean
        get() = expiresAt?.let { System.currentTimeMillis() > it } ?: false

    val isExpiringSoon: Boolean
        get() = expiresAt?.let {
            val remaining = it - System.currentTimeMillis()
            remaining in 1..(4 * 60 * 60 * 1000L)
        } ?: false

    val timeRemaining: Long
        get() = expiresAt?.let { maxOf(0, it - System.currentTimeMillis()) } ?: 0

    val hasFirstMessage: Boolean
        get() = firstMsgBy != null

    val iSentFirst: Boolean
        get() = firstMsgByMe

    val showCountdown: Boolean
        get() = expiresAt != null && !isExpired

    val callsUnlocked: Boolean
        get() = hasFirstMessage && !firstMsgLocked
}

data class LikedYouCard(
    val id: String = UUID.randomUUID().toString(),
    val user: User,
    val culturalScore: Int = 0,
    val culturalBadge: CulturalBadge = CulturalBadge.NONE,
    val likedAt: Long = System.currentTimeMillis(),
    /** Hinge-style note sent with the like ("Commented on your profile"). */
    val likeComment: String? = null
)

data class Icebreaker(
    val id: String = UUID.randomUUID().toString(),
    val question: String,
    val category: String
)
