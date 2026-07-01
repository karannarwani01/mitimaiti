import Foundation

struct Message: Identifiable, Codable, Hashable {
    static let allowedReactions: [String] = ["❤️", "😂", "😮", "😢", "😡", "👍"]

    let id: String
    let matchId: String
    let senderId: String
    var content: String
    var mediaUrl: String?
    var msgType: MessageType
    var status: MessageStatus
    let createdAt: Date
    var reaction: String?
    var durationSeconds: Int

    var isFromMe: Bool {
        senderId == "current-user-id"
    }

    init(
        id: String = UUID().uuidString,
        matchId: String,
        senderId: String,
        content: String,
        mediaUrl: String? = nil,
        msgType: MessageType = .text,
        status: MessageStatus = .sent,
        createdAt: Date = Date(),
        reaction: String? = nil,
        durationSeconds: Int = 0
    ) {
        self.id = id
        self.matchId = matchId
        self.senderId = senderId
        self.content = content
        self.mediaUrl = mediaUrl
        self.msgType = msgType
        self.status = status
        self.createdAt = createdAt
        self.reaction = reaction
        self.durationSeconds = durationSeconds
    }
}

struct Match: Identifiable, Codable, Hashable {
    let id: String
    let otherUser: User
    var status: MatchStatus
    let matchedAt: Date
    var expiresAt: Date?
    var lastMessage: Message?
    var unreadCount: Int
    var firstMsgBy: String?
    /// Server-computed: whether the current user sent the first message. Used
    /// for the Respect-First lock instead of comparing firstMsgBy to our own id
    /// (which the client doesn't reliably have). Optional so older/partial
    /// payloads that omit it decode cleanly (treated as false).
    var firstMsgByMe: Bool?
    var firstMsgLocked: Bool
    var firstMsgAt: Date?

    // MARK: - Timer Logic
    // The 24h dissolution timer is based on firstMsgAt (when first message was sent).
    // Before first message: expiresAt is 24h from matchedAt.
    // After first message: dissolution happens 24h after firstMsgAt if no reply.
    // After reply: timer is irrelevant, match stays active.

    /// Whether the match has been dissolved due to no reply within 24h
    var isExpired: Bool {
        guard let exp = expiresAt else { return false }
        return exp < Date()
    }

    /// Whether the match is expiring within 4 hours (critical zone)
    var isExpiringSoon: Bool {
        guard let exp = expiresAt else { return false }
        return exp.timeIntervalSinceNow < 4 * 3600 && exp.timeIntervalSinceNow > 0
    }

    /// Time remaining before dissolution (seconds)
    var timeRemaining: TimeInterval {
        guard let exp = expiresAt else { return 0 }
        return max(0, exp.timeIntervalSinceNow)
    }

    /// Whether either user has sent the first message
    var hasFirstMessage: Bool {
        firstMsgBy != nil
    }

    /// Whether the current user sent the first message
    var iSentFirst: Bool {
        firstMsgByMe ?? false
    }

    /// Whether the countdown timer should be visible
    /// Shows when: pending_first_message status, OR locked waiting for reply
    /// Hides when: chat is unlocked (both have messaged)
    var showCountdown: Bool {
        if !firstMsgLocked && hasFirstMessage {
            // Both users have exchanged messages — timer gone
            return false
        }
        // Still waiting for first message or waiting for reply
        return expiresAt != nil && !isExpired
    }

    /// Whether calls/video are unlocked (both users have messaged)
    var callsUnlocked: Bool {
        hasFirstMessage && !firstMsgLocked
    }

    init(
        id: String = UUID().uuidString,
        otherUser: User,
        status: MatchStatus = .pendingFirstMessage,
        matchedAt: Date = Date(),
        expiresAt: Date? = nil,
        lastMessage: Message? = nil,
        unreadCount: Int = 0,
        firstMsgBy: String? = nil,
        firstMsgByMe: Bool? = nil,
        firstMsgLocked: Bool = false,
        firstMsgAt: Date? = nil
    ) {
        self.id = id
        self.otherUser = otherUser
        self.status = status
        self.matchedAt = matchedAt
        self.expiresAt = expiresAt
        self.lastMessage = lastMessage
        self.unreadCount = unreadCount
        self.firstMsgBy = firstMsgBy
        self.firstMsgByMe = firstMsgByMe
        self.firstMsgLocked = firstMsgLocked
        self.firstMsgAt = firstMsgAt
    }
}

struct LikedYouCard: Identifiable, Codable, Hashable {
    let id: String
    let user: User
    let likedAt: Date
    var likeLabel: String
    var culturalScore: Int
    var culturalBadge: CulturalBadge

    init(
        id: String = UUID().uuidString,
        user: User,
        likedAt: Date = Date(),
        likeLabel: String = "Liked your profile",
        culturalScore: Int = 0,
        culturalBadge: CulturalBadge = .none
    ) {
        self.id = id
        self.user = user
        self.likedAt = likedAt
        self.likeLabel = likeLabel
        self.culturalScore = culturalScore
        self.culturalBadge = culturalBadge
    }
}

struct Icebreaker: Identifiable, Codable, Hashable {
    let id: String
    let category: String
    let question: String

    init(id: String = UUID().uuidString, category: String, question: String) {
        self.id = id
        self.category = category
        self.question = question
    }
}
