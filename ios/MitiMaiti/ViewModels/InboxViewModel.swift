import SwiftUI
import Combine

@MainActor
class InboxViewModel: ObservableObject {
    private var cancellables = Set<AnyCancellable>()
    @Published var likes: [LikedYouCard] = []
    @Published var matches: [Match] = []
    @Published var isLoading = false
    @Published var error: String?

    private let api = APIService.shared

    var totalLikes: Int { likes.count }
    var totalMatches: Int { matches.count }
    var unreadMessages: Int { matches.reduce(0) { $0 + $1.unreadCount } }

    private var previousLikeIds: Set<String> = []

    init() {
        // Real-time: the backend emits new_match / match_update over the
        // socket. Refresh the inbox and surface an in-app notification even
        // when the user isn't on the Discover screen. (These streams are
        // single-consumer; InboxViewModel is their only subscriber.)
        Task { @MainActor [weak self] in
            for await payload in SocketChat.shared.newMatches.stream {
                guard let self else { break }
                let name = (payload["displayName"] as? String) ?? "Someone"
                NotificationManager.shared.addNotification(
                    type: .match,
                    title: "New Match!",
                    body: "You and \(name) matched! Say hi before the timer runs out.",
                    actionData: payload["userId"] as? String
                )
                self.loadInbox()
            }
        }
        Task { @MainActor [weak self] in
            for await payload in SocketChat.shared.matchUpdates.stream {
                guard let self else { break }
                guard let matchId = payload["matchId"] as? String,
                      (payload["status"] as? String) == "active" else { continue }
                self.activateMatch(id: matchId)
            }
        }
        // Global message alerts: a user who is online but NOT inside this
        // chat gets no push (the server suppresses it) and previously nothing
        // in-app either. Bump the unread badge and surface a notification.
        SocketChat.shared.globalMessages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] payload in
                guard let self else { return }
                guard let matchId = payload["matchId"] as? String else { return }
                // The open chat handles its own messages
                if matchId == SocketChat.shared.activeChatMatchId { return }
                // Ignore the echo of our own sends (match room includes us)
                if let senderId = payload["senderId"] as? String,
                   senderId == Message.currentUserId { return }

                let content = (payload["content"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? "Sent you a message"

                if let idx = self.matches.firstIndex(where: { $0.id == matchId }) {
                    var match = self.matches[idx]
                    match.unreadCount += 1
                    match.lastMessage = Message(
                        matchId: matchId,
                        senderId: match.otherUser.id,
                        content: content,
                        createdAt: Date()
                    )
                    if match.iSentFirst {
                        match.firstMsgLocked = false
                        match.status = .active
                    }
                    self.matches.remove(at: idx)
                    self.matches.insert(match, at: 0)

                    NotificationManager.shared.addNotification(
                        type: .message,
                        title: match.otherUser.displayName,
                        body: content,
                        actionData: matchId
                    )
                } else {
                    // Unknown match (e.g. brand-new) — refresh from the server
                    self.loadInbox()
                }
            }
            .store(in: &cancellables)
    }

    func loadInbox() {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        Task {
            do {
                let result = try await api.fetchInbox()
                likes = result.likes
                matches = result.matches
                isLoading = false

                // Create notifications for new likes we haven't seen before
                let currentLikeIds = Set(likes.map(\.id))
                let newLikeIds = currentLikeIds.subtracting(previousLikeIds)
                if !previousLikeIds.isEmpty {
                    for like in likes where newLikeIds.contains(like.id) {
                        NotificationManager.shared.addNotification(
                            type: .like,
                            title: "\(like.user.displayName) liked your profile",
                            body: "Check Liked You to see who!",
                            actionData: like.user.id
                        )
                    }
                }
                previousLikeIds = currentLikeIds

                // Schedule expiry reminders for matches with expiration
                for match in matches {
                    if let expiresAt = match.expiresAt, expiresAt > Date() {
                        NotificationManager.shared.scheduleExpiryReminder(
                            matchName: match.otherUser.displayName,
                            expiresAt: expiresAt
                        )
                    }
                }
            } catch {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    func likeBack(likeId: String) {
        guard let index = likes.firstIndex(where: { $0.id == likeId }) else { return }
        let like = likes.remove(at: index)

        // Provisional match shown immediately — but with a placeholder id.
        // Opening a chat against that fake id 404s, so swap in the real
        // match_id from the action response as soon as it arrives.
        let provisionalId = "pending-\(like.user.id)"
        let expiresAt = Date().addingTimeInterval(86400)
        let match = Match(
            id: provisionalId,
            otherUser: like.user,
            status: .pendingFirstMessage,
            matchedAt: Date(),
            expiresAt: expiresAt,
            firstMsgLocked: true
        )
        matches.insert(match, at: 0)

        Task {
            if let result = try? await api.performAction(targetId: like.user.id, type: .like),
               let realId = result.matchId {
                if let idx = matches.firstIndex(where: { $0.id == provisionalId }) {
                    var fixed = matches[idx]
                    fixed = Match(
                        id: realId,
                        otherUser: fixed.otherUser,
                        status: fixed.status,
                        matchedAt: fixed.matchedAt,
                        expiresAt: fixed.expiresAt,
                        firstMsgLocked: fixed.firstMsgLocked
                    )
                    matches[idx] = fixed
                }
            } else {
                // No match id returned — fall back to the server's truth
                loadInbox()
            }
        }

        // Trigger match notification
        NotificationManager.shared.addNotification(
            type: .match,
            title: "New Match!",
            body: "You and \(like.user.displayName) matched! Say hi before the timer runs out.",
            actionData: like.user.id
        )

        // Schedule expiry reminders for this new match
        NotificationManager.shared.scheduleExpiryReminder(
            matchName: like.user.displayName,
            expiresAt: expiresAt
        )
    }

    func passLike(likeId: String) {
        guard let like = likes.first(where: { $0.id == likeId }) else { return }
        likes.removeAll { $0.id == likeId }
        // Record the pass so this liker doesn't reappear on the next refetch.
        Task { _ = try? await api.performAction(targetId: like.user.id, type: .pass) }
    }

    func unmatch(matchId: String) {
        matches.removeAll { $0.id == matchId }
    }

    /// Insert a freshly-created match immediately (e.g. from the Discover
    /// match popup) so the chat screen can open it before the next inbox
    /// refetch replaces it with the server copy.
    func upsertMatch(_ match: Match) {
        if !matches.contains(where: { $0.id == match.id }) {
            matches.insert(match, at: 0)
        }
        loadInbox()
    }

    /// Called when a reply is received after an ice breaker / first message.
    /// Moves the match from the timer-avatar section to the permanent Chats list.
    func activateMatch(id: String) {
        guard let index = matches.firstIndex(where: { $0.id == id }) else { return }
        matches[index].status = .active
        matches[index].expiresAt = nil
    }
}
