import SwiftUI

@MainActor
class FeedViewModel: ObservableObject {
    @Published var cards: [FeedCard] = []
    @Published var isLoading = false
    @Published var dailyLikesUsed = 0
    @Published var dailyRewindsUsed = 0
    @Published var showMatchAlert = false
    @Published var matchedUser: User?
    @Published var error: String?
    @Published var showScoreBreakdown = false
    @Published var selectedCard: FeedCard?

    let maxDailyLikes = 50
    let maxDailyRewinds = 10
    private var passedCards: [FeedCard] = []
    private let api = APIService.shared

    var likesRemaining: Int { maxDailyLikes - dailyLikesUsed }
    var rewindsRemaining: Int { maxDailyRewinds - dailyRewindsUsed }

    func loadFeed() {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        Task {
            do {
                let feed = try await api.fetchFeed()
                cards = feed
                isLoading = false
            } catch {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    func likeUser() {
        guard !cards.isEmpty else { return }
        guard dailyLikesUsed < maxDailyLikes else {
            error = "You've used all 50 likes for today!"
            return
        }

        let card = cards.removeFirst()
        dailyLikesUsed += 1

        Task {
            do {
                let result = try await api.performAction(targetId: card.user.id, type: .like)
                if result.isMatch {
                    matchedUser = card.user
                    showMatchAlert = true

                    // Trigger match notification
                    NotificationManager.shared.addNotification(
                        type: .match,
                        title: "New Match!",
                        body: "You and \(card.user.displayName) matched! Say hi before the timer runs out.",
                        actionData: card.user.id
                    )
                }
            } catch {
                self.error = error.localizedDescription
            }
        }

        prefetchIfNeeded()
    }

    func passUser() {
        guard !cards.isEmpty else { return }
        let card = cards.removeFirst()
        passedCards.append(card)
        Task {
            // Record the pass on the backend so the profile isn't re-served in
            // the feed and rewind has something to undo (matches Android).
            // Fire-and-forget; a failed pass is non-fatal.
            _ = try? await api.performAction(targetId: card.user.id, type: .pass)
        }
        prefetchIfNeeded()
    }

    func rewind() {
        guard dailyRewindsUsed < maxDailyRewinds else {
            error = "You've used all 10 rewinds for today!"
            return
        }
        guard let last = passedCards.popLast() else {
            error = "Nothing to rewind!"
            return
        }
        cards.insert(last, at: 0)
        dailyRewindsUsed += 1
        // Undo the pass on the backend too so the profile's state matches the UI
        // (matches Android). Fire-and-forget; a failed rewind is non-fatal.
        Task { _ = try? await api.rewind() }
    }

    private func prefetchIfNeeded() {
        if cards.count <= 5 {
            Task {
                if let more = try? await api.fetchFeed() {
                    let existingIds = Set(cards.map(\.id))
                    let newCards = more.filter { !existingIds.contains($0.id) }
                    cards.append(contentsOf: newCards)
                }
            }
        }
    }
}
