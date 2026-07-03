import SwiftUI

@MainActor
class FeedViewModel: ObservableObject {
    @Published var cards: [FeedCard] = []
    @Published var isLoading = false
    @Published var dailyLikesUsed = 0
    @Published var dailyRewindsUsed = 0
    @Published var dailyCommentsUsed = 0
    @Published var showMatchAlert = false
    @Published var matchedUser: User?
    @Published var matchedMatchId: String?
    @Published var error: String?
    @Published var showScoreBreakdown = false
    @Published var selectedCard: FeedCard?

    let maxDailyLikes = 50
    let maxDailyRewinds = 10
    let maxDailyComments = 5

    /// Last swipes in order (card + kind), so rewind undoes likes AND passes
    /// — matching the backend, which deletes the most recent swipe of either
    /// kind (previously undoing after a like restored the wrong profile).
    private enum SwipeKind { case like, pass }
    private var swipeHistory: [(card: FeedCard, kind: SwipeKind, hadComment: Bool)] = []

    private let api = APIService.shared

    var likesRemaining: Int { maxDailyLikes - dailyLikesUsed }
    var rewindsRemaining: Int { maxDailyRewinds - dailyRewindsUsed }
    var commentsRemaining: Int { max(0, maxDailyComments - dailyCommentsUsed) }

    /// Seed daily counters from the server so they survive relaunch.
    private func applyLimits(_ limits: APIService.DailyLimits?) {
        if let used = limits?.likesUsedToday { dailyLikesUsed = used }
        if let used = limits?.rewindsUsedToday { dailyRewindsUsed = used }
        if let used = limits?.commentsUsedToday { dailyCommentsUsed = used }
    }

    // ── "Most Compatible" daily pick (Hinge Standouts-style) ──
    @Published var dailyPick: FeedCard?

    private func loadDailyPick() {
        Task {
            if let pick = try? await api.fetchDailyPick() {
                dailyPick = pick
            }
        }
    }

    /// Bring today's pick to the front of the deck so the user can swipe on it.
    func bringPickToFront() {
        guard let pick = dailyPick else { return }
        let existing = cards.first { $0.id == pick.id }
        cards.removeAll { $0.id == pick.id }
        cards.insert(existing ?? pick, at: 0)
    }

    /// Hide the pick banner once the user has swiped on that person.
    private func clearPickIfActedOn(_ cardId: String) {
        if dailyPick?.id == cardId { dailyPick = nil }
    }

    func loadFeed() {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        loadDailyPick()

        Task {
            do {
                let feed = try await api.fetchFeed()
                cards = feed.cards
                applyLimits(feed.limits)
                isLoading = false
            } catch {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    /// Persist the Discover filter sheet to the backend (user_settings drives
    /// the feed query server-side), then reload the deck. Previously "Show
    /// Results" only dismissed the sheet and the feed never changed.
    func applyFilters(_ settings: [String: Any]) {
        Task {
            _ = try? await api.patchMe(["settings": settings])
            isLoading = true
            error = nil
            do {
                let feed = try await api.fetchFeed()
                cards = feed.cards
                applyLimits(feed.limits)
                isLoading = false
            } catch {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    func likeUser(comment: String? = nil, expectedTopCardId: String? = nil) {
        guard !cards.isEmpty else { return }
        // A comment written for one card must never land on another — if the
        // deck head changed while the sheet was open, abort instead.
        if let expected = expectedTopCardId, cards.first?.id != expected {
            error = "That profile isn't on top anymore — try again."
            return
        }
        guard dailyLikesUsed < maxDailyLikes else {
            error = "You've used all \(maxDailyLikes) likes for today. Come back tomorrow!"
            return
        }
        let note = comment?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasNote = note?.isEmpty == false
        if hasNote, dailyCommentsUsed >= maxDailyComments {
            error = "You've used all \(maxDailyComments) comments for today — you can still send a regular like."
            return
        }

        let card = cards.removeFirst()
        dailyLikesUsed += 1
        if hasNote { dailyCommentsUsed += 1 }
        swipeHistory.append((card, .like, hasNote))
        clearPickIfActedOn(card.id)

        Task {
            do {
                let result = try await api.performAction(targetId: card.user.id, type: .like, comment: hasNote ? note : nil)
                if let used = result.likesUsedToday { dailyLikesUsed = used }
                if let used = result.commentsUsedToday { dailyCommentsUsed = used }
                if hasNote, result.commentSaved == false {
                    self.error = "Your like was sent, but the note couldn't be attached this time."
                }
                if result.isMatch {
                    // A matched like can't be rewound — drop it from the undo stack
                    swipeHistory.removeAll { $0.card.id == card.id }
                    matchedUser = card.user
                    matchedMatchId = result.matchId
                    showMatchAlert = true

                    // Trigger match notification
                    NotificationManager.shared.addNotification(
                        type: .match,
                        title: "New Match!",
                        body: "You and \(card.user.displayName) matched! Say hi before the timer runs out.",
                        actionData: card.user.id
                    )
                }
            } catch APIError.commentLimitReached {
                // The like was NOT recorded — restore the card so the user can
                // re-like without a note.
                dailyCommentsUsed = maxDailyComments
                if dailyLikesUsed > 0 { dailyLikesUsed -= 1 }
                swipeHistory.removeAll { $0.card.id == card.id }
                cards.insert(card, at: 0)
                self.error = "You've used all \(maxDailyComments) comments for today — try again with a regular like."
            } catch APIError.rateLimited {
                dailyLikesUsed = maxDailyLikes
                self.error = "You've used all \(maxDailyLikes) likes for today. Come back tomorrow!"
            } catch {
                self.error = error.localizedDescription
            }
        }

        prefetchIfNeeded()
    }

    func passUser() {
        guard !cards.isEmpty else { return }
        let card = cards.removeFirst()
        swipeHistory.append((card, .pass, false))
        clearPickIfActedOn(card.id)
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
            error = "You've used all \(maxDailyRewinds) rewinds for today."
            return
        }
        guard let last = swipeHistory.popLast() else {
            error = "Nothing to rewind!"
            return
        }
        cards.insert(last.card, at: 0)
        dailyRewindsUsed += 1
        if last.kind == .like, dailyLikesUsed > 0 { dailyLikesUsed -= 1 }
        if last.hadComment, dailyCommentsUsed > 0 { dailyCommentsUsed -= 1 }
        Task {
            do {
                _ = try await api.rewind()
            } catch let APIError.serverError(msg) where msg.contains("match") {
                // The like became a match server-side — take the card back off the deck
                cards.removeAll { $0.id == last.card.id }
                self.error = "It's already a match! Unmatch from the chat instead."
            } catch {
                // Non-fatal — the UI card stays restored
            }
        }
    }

    private func prefetchIfNeeded() {
        if cards.count <= 5 {
            Task {
                if let more = try? await api.fetchFeed() {
                    let existingIds = Set(cards.map(\.id))
                    let newCards = more.cards.filter { !existingIds.contains($0.id) }
                    cards.append(contentsOf: newCards)
                    applyLimits(more.limits)
                }
            }
        }
    }
}
