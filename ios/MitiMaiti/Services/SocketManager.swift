import Foundation
import Combine
import SocketIO

/// WebSocket manager for real-time chat. Mirrors backend/src/socket.ts events.
///
/// Events sent: send_msg, typing, enter_chat, leave_chat, heartbeat
/// Events received: new_msg, typing, msg_read, match_update, new_match, error
@MainActor
final class SocketChat: ObservableObject {
    static let shared = SocketChat()

    @Published private(set) var isConnected = false

    private var manager: SocketManager?
    private var socket: SocketIOClient?

    private(set) var incomingMessages = AsyncStream<[String: Any]>.makeStream()
    private(set) var typingEvents = AsyncStream<[String: Any]>.makeStream()
    private(set) var readReceipts = AsyncStream<[String: Any]>.makeStream()
    private(set) var matchUpdates = AsyncStream<[String: Any]>.makeStream()
    private(set) var newMatches = AsyncStream<[String: Any]>.makeStream()
    /// Fires on RE-connects (not the initial connect) so open chats can
    /// backfill messages that arrived during the outage.
    private(set) var reconnects = AsyncStream<Void>.makeStream()
    private var wasEverConnected = false

    /// Multicast copy of every new_msg — the AsyncStream above is
    /// single-consumer (owned by the open ChatViewModel), so global listeners
    /// (inbox badge / in-app alerts) subscribe here instead.
    let globalMessages = PassthroughSubject<[String: Any], Never>()

    /// The match whose chat screen is currently open (nil = none). Global
    /// listeners use this to avoid double-notifying for the visible chat.
    var activeChatMatchId: String?

    func connect(token: String) {
        if socket?.status == .connected { return }
        guard let url = URL(string: AppConfig.socketURL) else { return }

        manager = SocketManager(socketURL: url, config: [
            .log(false),
            .compress,
            .reconnects(true),
            .reconnectAttempts(10),
            .reconnectWait(1),
            .reconnectWaitMax(5),
            .connectParams(["token": token])
        ])
        socket = manager?.defaultSocket

        socket?.on(clientEvent: .connect) { [weak self] _, _ in
            guard let self else { return }
            self.isConnected = true
            self.socket?.emit("heartbeat")
            if self.wasEverConnected { self.reconnects.continuation.yield(()) }
            self.wasEverConnected = true
        }
        socket?.on(clientEvent: .disconnect) { [weak self] _, _ in
            self?.isConnected = false
        }
        socket?.on("new_msg") { [weak self] data, _ in
            if let payload = data.first as? [String: Any] {
                self?.incomingMessages.continuation.yield(payload)
                self?.globalMessages.send(payload)
            }
        }
        socket?.on("typing") { [weak self] data, _ in
            if let payload = data.first as? [String: Any] {
                self?.typingEvents.continuation.yield(payload)
            }
        }
        // Backend emits 'messages_read' (payload { matchId, readBy, readAt })
        socket?.on("messages_read") { [weak self] data, _ in
            if let payload = data.first as? [String: Any] {
                self?.readReceipts.continuation.yield(payload)
            }
        }
        socket?.on("match_update") { [weak self] data, _ in
            if let payload = data.first as? [String: Any] {
                self?.matchUpdates.continuation.yield(payload)
            }
        }
        socket?.on("new_match") { [weak self] data, _ in
            if let payload = data.first as? [String: Any] {
                self?.newMatches.continuation.yield(payload)
            }
        }
        socket?.on("error") { data, _ in
            print("[SocketChat] error:", data)
        }

        socket?.connect()
    }

    func disconnect() {
        socket?.disconnect()
        socket = nil
        manager = nil
        isConnected = false
    }

    // MARK: - Send events

    func sendMessage(matchId: String, content: String, msgType: String = "text") {
        socket?.emit("send_msg", ["matchId": matchId, "content": content, "msgType": msgType])
    }

    func sendTyping(matchId: String) {
        socket?.emit("typing", ["matchId": matchId])
    }

    func enterChat(matchId: String) {
        socket?.emit("enter_chat", ["matchId": matchId])
    }

    func leaveChat(matchId: String) {
        socket?.emit("leave_chat", ["matchId": matchId])
    }

    func sendHeartbeat() {
        socket?.emit("heartbeat")
    }
}
