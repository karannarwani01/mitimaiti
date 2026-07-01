import SwiftUI

@MainActor
class InboxViewModel: ObservableObject {
    @Published var likes: [LikedYouCard] = []
    @Published var matches: [Match] = []
    @Published var isLoading = false
    @Published var error: String?

    private let api = APIService.shared

    var totalLikes: Int { likes.count }
    var totalMatches: Int { matches.count }
    var unreadMessages: Int { matches.reduce(0) { $0 + $1.unreadCount } }

    private var previousLikeIds: Set<String> = []

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

        let expiresAt = Date().addingTimeInterval(86400)
        let match = Match(
            otherUser: like.user,
            status: .pendingFirstMessage,
            matchedAt: Date(),
            expiresAt: expiresAt,
            firstMsgLocked: true
        )
        matches.insert(match, at: 0)

        // Persist the like so the match is actually created server-side (they
        // already liked us → mutual match). Without this the match is cosmetic
        // and vanishes on the next inbox refetch.
        Task { _ = try? await api.performAction(targetId: like.user.id, type: .like) }

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
        likes.removeAll { $0.id == likeId }
    }

    func unmatch(matchId: String) {
        matches.removeAll { $0.id == matchId }
    }

    /// Called when a reply is received after an ice breaker / first message.
    /// Moves the match from the timer-avatar section to the permanent Chats list.
    func activateMatch(id: String) {
        guard let index = matches.firstIndex(where: { $0.id == id }) else { return }
        matches[index].status = .active
        matches[index].expiresAt = nil
    }
}
