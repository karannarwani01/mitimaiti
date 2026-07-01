import SwiftUI
import Combine

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var messageText = ""
    @Published var isLoading = false
    @Published var isSending = false
    @Published var isOtherTyping = false
    @Published var match: Match?
    @Published var error: String?
    @Published var chatUnlocked = false

    private let api = APIService.shared
    private let currentUserId = "current-user-id"

    /// Injected so that when a reply unlocks the match we can update the
    /// shared InboxViewModel and move the match into the Chats section.
    weak var inboxViewModel: InboxViewModel?

    var hasMessages: Bool { !messages.isEmpty }

    // MARK: - Respect-First Lock State

    /// Whether the chat is in "locked" state:
    /// - The current user sent the first message
    /// - The other user has NOT replied yet
    /// - Current user CANNOT send another message until they reply
    var isLockedForMe: Bool {
        guard let match else { return false }
        // If match says locked AND I'm the one who sent first → I'm blocked.
        // iSentFirst uses the server-computed firstMsgByMe flag.
        return match.firstMsgLocked && match.iSentFirst
    }

    /// Whether the other user needs to send the first message
    /// (match exists but nobody has messaged yet)
    var awaitingFirstMessage: Bool {
        guard let match else { return false }
        return !match.hasFirstMessage
    }

    /// Whether the countdown timer should show
    var showCountdown: Bool {
        match?.showCountdown ?? false
    }

    /// Dynamic banner message based on lock state
    var lockBannerMessage: (title: String, subtitle: String)? {
        guard let match else { return nil }

        if !match.hasFirstMessage {
            // No one has messaged yet
            return ("Send the first message!", "Break the ice before the timer runs out")
        }

        if match.firstMsgLocked && match.iSentFirst {
            // I sent first, waiting for their reply
            return ("Waiting for reply...", "Your message has been sent. You can send another message once \(match.otherUser.displayName) replies.")
        }

        if match.firstMsgLocked && !match.iSentFirst {
            // They sent first, I need to reply
            return ("\(match.otherUser.displayName) sent the first message!", "Reply to keep the conversation going")
        }

        return nil
    }

    /// Whether the text input should be disabled
    var inputDisabled: Bool {
        isLockedForMe
    }

    /// Placeholder text for the input field
    var inputPlaceholder: String {
        if isLockedForMe {
            return "Waiting for \(match?.otherUser.displayName ?? "them") to reply..."
        }
        if awaitingFirstMessage {
            return "Send the first message..."
        }
        return "Type a message..."
    }

    // MARK: - Load Messages

    func loadMessages(for match: Match) {
        self.match = match
        startRealtime()
        SocketChat.shared.enterChat(matchId: match.id)

        // Serve from cache immediately — avoids blank screen on re-navigation
        let cached = MessageRepository.shared.getMessages(matchId: match.id)
        if !cached.isEmpty {
            messages = cached
            checkAndUnlockIfReplied()
            return
        }

        isLoading = true

        Task {
            do {
                let msgs = try await api.fetchMessages(matchId: match.id)
                messages = msgs.sorted { $0.createdAt < $1.createdAt }
                MessageRepository.shared.setMessages(matchId: match.id, msgs: messages)
                isLoading = false

                // Check if the other user has already replied (unlock state)
                checkAndUnlockIfReplied()
            } catch {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    // MARK: - Send Message

    func sendMessage() {
        // If we're editing, route to saveEdit instead
        if editingMessageId != nil {
            saveEdit()
            return
        }
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let matchId = match?.id else { return }

        // Respect-First enforcement: block if locked for me
        if isLockedForMe {
            error = "Please wait for \(match?.otherUser.displayName ?? "them") to reply to your first message."
            return
        }

        let tempMsg = Message(
            matchId: matchId,
            senderId: currentUserId,
            content: text,
            status: .sending
        )
        messages.append(tempMsg)
        messageText = ""
        isSending = true

        // If this is the first message in the match, engage the lock
        let isFirstMessage = !match!.hasFirstMessage

        Task {
            do {
                let sent = try await api.sendMessage(matchId: matchId, content: text)
                if let idx = messages.firstIndex(where: { $0.id == tempMsg.id }) {
                    messages[idx] = sent
                }
                MessageRepository.shared.setMessages(matchId: matchId, msgs: messages)
                isSending = false

                if isFirstMessage {
                    // Lock engaged: I sent first, now waiting for their reply
                    match?.firstMsgBy = currentUserId; match?.firstMsgByMe = true
                    match?.firstMsgLocked = true
                    match?.firstMsgAt = Date()
                }

                // Real replies now arrive via SocketChat (no simulation).
            } catch {
                self.error = error.localizedDescription
                isSending = false
            }
        }
    }

    @Published var editingMessageId: String? = nil

    func startEdit(_ message: Message) {
        guard message.msgType == .text else { return }
        editingMessageId = message.id
        var text = message.content
        if text.hasSuffix(" [edited]") {
            text = String(text.dropLast(" [edited]".count))
        } else if text.hasSuffix("[edited]") {
            text = String(text.dropLast("[edited]".count))
        }
        messageText = text.trimmingCharacters(in: .whitespaces)
    }

    func cancelEdit() {
        editingMessageId = nil
        messageText = ""
    }

    func saveEdit() {
        guard let id = editingMessageId, let matchId = match?.id else { return }
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let withMarker = trimmed.contains("[edited]") ? trimmed : "\(trimmed) [edited]"
        if let idx = messages.firstIndex(where: { $0.id == id }) {
            messages[idx].content = withMarker
            MessageRepository.shared.setMessages(matchId: matchId, msgs: messages)
        }
        editingMessageId = nil
        messageText = ""
        // Persist to the backend so the edit survives a chat reload. Send the
        // raw text; the server owns the " [edited]" marker.
        Task { try? await api.editMessage(matchId: matchId, messageId: id, content: trimmed) }
    }

    func toggleReaction(_ message: Message, emoji: String) {
        guard Message.allowedReactions.contains(emoji) else { return }
        guard let matchId = match?.id else { return }
        if let idx = messages.firstIndex(where: { $0.id == message.id }) {
            let removing = messages[idx].reaction == emoji
            messages[idx].reaction = removing ? nil : emoji
            MessageRepository.shared.setMessages(matchId: matchId, msgs: messages)
            // Persist to the backend so the reaction survives a chat reload.
            Task {
                if removing { try? await api.clearReaction(matchId: matchId, messageId: message.id) }
                else { try? await api.setReaction(matchId: matchId, messageId: message.id, emoji: emoji) }
            }
        }
    }

    /// Dissolve this match on the backend and remove it from the inbox locally.
    func unmatch() {
        guard let matchId = match?.id else { return }
        inboxViewModel?.unmatch(matchId: matchId)
        Task { try? await api.unmatch(matchId: matchId) }
    }

    /// Block the other user (auto-unmatches server-side) and drop the match locally.
    func block() {
        guard let match else { return }
        inboxViewModel?.unmatch(matchId: match.id)
        Task { try? await api.blockUser(userId: match.otherUser.id) }
    }

    func deleteMessage(_ message: Message) {
        guard let matchId = match?.id else { return }
        messages.removeAll { $0.id == message.id }
        MessageRepository.shared.setMessages(matchId: matchId, msgs: messages)
        if editingMessageId == message.id {
            cancelEdit()
        }
        // Persist to the backend so the delete survives a chat reload.
        Task { try? await api.deleteMessage(matchId: matchId, messageId: message.id) }
    }

    func sendVoice(localUrl: String, durationSeconds: Int) {
        guard let matchId = match?.id else { return }
        if isLockedForMe {
            error = "Please wait for \(match?.otherUser.displayName ?? "them") to reply to your first message."
            return
        }

        let isFirstMessage = !match!.hasFirstMessage

        let msg = Message(
            matchId: matchId,
            senderId: currentUserId,
            content: "",
            mediaUrl: localUrl,
            msgType: .voice,
            status: .sent,
            durationSeconds: durationSeconds
        )
        messages.append(msg)
        MessageRepository.shared.setMessages(matchId: matchId, msgs: messages)

        if isFirstMessage {
            match?.firstMsgBy = currentUserId; match?.firstMsgByMe = true
            match?.firstMsgLocked = true
            match?.firstMsgAt = Date()
        }

        // Upload the recorded clip so it actually reaches the other user.
        if let url = URL(string: localUrl), let data = try? Data(contentsOf: url) {
            Task { _ = try? await api.sendChatVoice(matchId: matchId, audioData: data, durationSeconds: durationSeconds) }
        }
    }

    func sendImage(localUrl: String) {
        guard let matchId = match?.id else { return }
        if isLockedForMe {
            error = "Please wait for \(match?.otherUser.displayName ?? "them") to reply to your first message."
            return
        }

        let isFirstMessage = !match!.hasFirstMessage

        let msg = Message(
            matchId: matchId,
            senderId: currentUserId,
            content: "",
            mediaUrl: localUrl,
            msgType: .photo,
            status: .sent
        )
        messages.append(msg)
        MessageRepository.shared.setMessages(matchId: matchId, msgs: messages)

        if isFirstMessage {
            match?.firstMsgBy = currentUserId; match?.firstMsgByMe = true
            match?.firstMsgLocked = true
            match?.firstMsgAt = Date()
        }

        // Upload the picked file so it actually reaches the other user (the
        // camera/gallery path passes a local file URL; PhotosPicker uses
        // sendPhoto(imageData:) which already uploads).
        if let url = URL(string: localUrl), let data = try? Data(contentsOf: url) {
            Task { _ = try? await api.sendChatMedia(matchId: matchId, imageData: data) }
        }
    }

    /// Real-backend photo upload (added on the Mac side via APIService.sendChatMedia).
    func sendPhoto(imageData: Data) {
        guard let matchId = match?.id else { return }
        if isLockedForMe {
            error = "Please wait for \(match?.otherUser.displayName ?? "them") to reply to your first message."
            return
        }
        let tempMsg = Message(matchId: matchId, senderId: currentUserId,
                              content: "Uploading...", msgType: .photo, status: .sending)
        messages.append(tempMsg)
        let isFirstMessage = !match!.hasFirstMessage
        isSending = true

        Task {
            do {
                let sent = try await api.sendChatMedia(matchId: matchId, imageData: imageData)
                if let idx = messages.firstIndex(where: { $0.id == tempMsg.id }) {
                    messages[idx] = sent
                }
                MessageRepository.shared.setMessages(matchId: matchId, msgs: messages)
                isSending = false
                if isFirstMessage {
                    match?.firstMsgBy = currentUserId; match?.firstMsgByMe = true
                    match?.firstMsgLocked = true
                    match?.firstMsgAt = Date()
                }
            } catch {
                self.error = error.localizedDescription
                if let idx = messages.firstIndex(where: { $0.id == tempMsg.id }) {
                    messages.remove(at: idx)
                }
                isSending = false
            }
        }
    }

    func sendIcebreaker(_ question: String) {
        guard let matchId = match?.id else { return }

        // Icebreakers also count as first message
        if isLockedForMe {
            error = "Please wait for \(match?.otherUser.displayName ?? "them") to reply first."
            return
        }

        let isFirstMessage = !match!.hasFirstMessage

        let msg = Message(
            matchId: matchId,
            senderId: currentUserId,
            content: question,
            msgType: .icebreaker,
            status: .sending
        )
        messages.append(msg)

        Task {
            do {
                let sent = try await api.sendMessage(matchId: matchId, content: question, type: .icebreaker)
                if let idx = messages.firstIndex(where: { $0.id == msg.id }) {
                    messages[idx] = sent
                }
                MessageRepository.shared.setMessages(matchId: matchId, msgs: messages)

                if isFirstMessage {
                    match?.firstMsgBy = currentUserId; match?.firstMsgByMe = true
                    match?.firstMsgLocked = true
                    match?.firstMsgAt = Date()
                }

                // Real replies now arrive via SocketChat (no simulation).
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: - Receive Message (from other user)

    /// Called when a message arrives from the other user (via the socket)
    func receiveMessage(_ message: Message) {
        messages.append(message)
        if let matchId = match?.id {
            MessageRepository.shared.addMessage(matchId: matchId, message: message)
        }

        // Trigger a message notification
        if let match {
            NotificationManager.shared.addNotification(
                type: .message,
                title: "New message from \(match.otherUser.displayName)",
                body: message.content,
                actionData: match.id
            )
        }

        // If the match was locked and the other user just replied → UNLOCK
        if let match, match.firstMsgLocked {
            // The other user has replied — unlock the conversation
            self.match?.firstMsgLocked = false
            self.chatUnlocked = true

            // Match is now fully active: no expiry, promote status
            self.match?.expiresAt = nil
            self.match?.status = .active

            // Propagate to InboxViewModel so MatchesView moves the row
            // from the timer-avatar section into the permanent Chats list.
            inboxViewModel?.activateMatch(id: match.id)
        }
    }

    // MARK: - Check & Unlock

    /// After loading messages, check if the other user has already replied
    private func checkAndUnlockIfReplied() {
        guard let match, match.firstMsgLocked, match.firstMsgBy == currentUserId else { return }

        let otherUserId = match.otherUser.id
        let hasReply = messages.contains { $0.senderId == otherUserId }

        if hasReply {
            // Other user has already replied — unlock
            self.match?.firstMsgLocked = false
            self.chatUnlocked = true
            self.match?.expiresAt = nil
            self.match?.status = .active

            // Propagate to InboxViewModel so MatchesView reflects the change
            inboxViewModel?.activateMatch(id: match.id)
        }
    }

    // MARK: - Mark Messages As Read

    /// Marks all unread messages from the other user as "read"
    func markUnreadMessagesAsRead() {
        guard let match else { return }
        let otherUserId = match.otherUser.id
        for i in messages.indices {
            if messages[i].senderId == otherUserId &&
               (messages[i].status == .sent || messages[i].status == .delivered) {
                messages[i].status = .read
            }
        }
    }

    // MARK: - Real-time (SocketChat)

    private var didStartRealtime = false
    private var typingResetTask: Task<Void, Never>?

    /// Subscribe once to the live socket streams for message/typing/read events.
    private func startRealtime() {
        guard !didStartRealtime else { return }
        didStartRealtime = true

        // Note: the socket exposes single-consumer AsyncStreams, so break out of
        // each loop once this view model is gone to free the stream for the next
        // chat's view model (rather than silently draining its events).
        Task { @MainActor [weak self] in
            for await payload in SocketChat.shared.incomingMessages.stream {
                guard let self else { break }
                self.handleIncoming(payload)
            }
        }
        Task { @MainActor [weak self] in
            for await payload in SocketChat.shared.typingEvents.stream {
                guard let self else { break }
                guard payload["matchId"] as? String == self.match?.id else { continue }
                self.isOtherTyping = true
                self.typingResetTask?.cancel()
                self.typingResetTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    self?.isOtherTyping = false
                }
            }
        }
        Task { @MainActor [weak self] in
            for await payload in SocketChat.shared.readReceipts.stream {
                guard let self else { break }
                guard payload["matchId"] as? String == self.match?.id else { continue }
                for i in self.messages.indices where self.messages[i].isFromMe {
                    self.messages[i].status = .read
                }
            }
        }
    }

    /// Accept only the OTHER user's messages — our own are already shown
    /// optimistically and the backend echoes them back to us.
    private func handleIncoming(_ payload: [String: Any]) {
        guard let mid = match?.id, payload["matchId"] as? String == mid else { return }
        guard let otherId = match?.otherUser.id, payload["senderId"] as? String == otherId else { return }
        let msg = parseSocketMessage(payload)
        if messages.contains(where: { $0.id == msg.id }) { return }
        isOtherTyping = false
        receiveMessage(msg)
    }

    /// Parse a socket new_msg payload (camelCase keys, not the REST snake_case).
    private func parseSocketMessage(_ p: [String: Any]) -> Message {
        let typeStr = p["msgType"] as? String ?? "text"
        return Message(
            id: p["id"] as? String ?? UUID().uuidString,
            matchId: p["matchId"] as? String ?? "",
            senderId: p["senderId"] as? String ?? "",
            content: p["content"] as? String ?? "",
            mediaUrl: p["mediaUrl"] as? String,
            msgType: MessageType(rawValue: typeStr) ?? .text,
            status: .delivered,
            createdAt: Date()
        )
    }
}
