import Foundation

struct Message: Identifiable, Codable, Hashable {
    static let allowedReactions: [String] = ["❤️", "😂", "😮", "😢", "😡", "👍"]

    /// The logged-in user's real id, set at login/session restore. Messages
    /// fetched from the backend carry real UUIDs — comparing only against the
    /// optimistic "current-user-id" marker rendered every server-loaded
    /// message (including your own) on the other person's side.
    nonisolated(unsafe) static var currentUserId: String?

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
    /// Server-computed ownership flag (GET /chat sends `isYou`); most reliable
    /// signal when present.
    var isYouFlag: Bool?

    var isFromMe: Bool {
        if let isYouFlag { return isYouFlag }
        return senderId == "current-user-id" ||
            (Message.currentUserId != nil && senderId == Message.currentUserId)
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
        durationSeconds: Int = 0,
        isYouFlag: Bool? = nil
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
        self.isYouFlag = isYouFlag
    }

    enum CodingKeys: String, CodingKey {
        case id, matchId, senderId, content, mediaUrl, msgType, status,
             createdAt, reaction, durationSeconds, isRead, isYou
    }

    /// Lenient decoding: GET /chat message rows omit matchId/status/
    /// durationSeconds, content can be null, and read state arrives as isRead.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        matchId = try c.decodeIfPresent(String.self, forKey: .matchId) ?? ""
        senderId = try c.decodeIfPresent(String.self, forKey: .senderId) ?? ""
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        mediaUrl = try c.decodeIfPresent(String.self, forKey: .mediaUrl)
        msgType = ((try? c.decodeIfPresent(MessageType.self, forKey: .msgType)) ?? nil) ?? .text
        if let s = ((try? c.decodeIfPresent(MessageStatus.self, forKey: .status)) ?? nil) {
            status = s
        } else if ((try? c.decodeIfPresent(Bool.self, forKey: .isRead)) ?? nil) == true {
            status = .read
        } else {
            status = .delivered
        }
        createdAt = ((try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? nil) ?? Date()
        reaction = try c.decodeIfPresent(String.self, forKey: .reaction)
        let explicitDuration = try c.decodeIfPresent(Int.self, forKey: .durationSeconds)
        // Voice messages store their duration (seconds) in `content`
        let voiceDuration = Int(content)
        durationSeconds = explicitDuration ?? ((msgType == .voice ? voiceDuration : nil) ?? 0)
        isYouFlag = try c.decodeIfPresent(Bool.self, forKey: .isYou)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(matchId, forKey: .matchId)
        try c.encode(senderId, forKey: .senderId)
        try c.encode(content, forKey: .content)
        try c.encodeIfPresent(mediaUrl, forKey: .mediaUrl)
        try c.encode(msgType, forKey: .msgType)
        try c.encode(status, forKey: .status)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(reaction, forKey: .reaction)
        try c.encode(durationSeconds, forKey: .durationSeconds)
        try c.encodeIfPresent(isYouFlag, forKey: .isYou)
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
    /// Each match can be extended by 24h exactly once (Bumble-style).
    /// Optional so older/partial payloads decode cleanly (treated as false).
    var extendedOnce: Bool?

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
        firstMsgAt: Date? = nil,
        extendedOnce: Bool? = nil
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
        self.extendedOnce = extendedOnce
    }
}

struct LikedYouCard: Identifiable, Codable, Hashable {
    let id: String
    let user: User
    let likedAt: Date
    var likeLabel: String
    /// Hinge-style note sent with the like ("Commented on your profile").
    var likeComment: String?
    var culturalScore: Int
    var culturalBadge: CulturalBadge

    init(
        id: String = UUID().uuidString,
        user: User,
        likedAt: Date = Date(),
        likeLabel: String = "Liked your profile",
        likeComment: String? = nil,
        culturalScore: Int = 0,
        culturalBadge: CulturalBadge = .none
    ) {
        self.id = id
        self.user = user
        self.likedAt = likedAt
        self.likeLabel = likeLabel
        self.likeComment = likeComment
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
