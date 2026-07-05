import SwiftUI
import PhotosUI
import AVFoundation
import UIKit

struct ChatView: View {
    let match: Match
    @StateObject private var chatVM = ChatViewModel()
    @EnvironmentObject private var inboxVM: InboxViewModel
    @Environment(\.adaptiveColors) private var colors
    @Environment(\.dismiss) private var dismiss
    private let localization = LocalizationManager.shared
    @FocusState private var isInputFocused: Bool

    // Toast
    @State private var showUnlockToast = false

    // Header menu / modals
    @State private var showMoreMenu     = false
    @State private var showUnmatchAlert = false
    @State private var showBlockAlert   = false
    @State private var showReportSheet  = false

    // Image viewer + picker
    @State private var viewerImageUrl: String? = nil
    @State private var photoErrorMessage: String? = nil
    @State private var showAttachmentChooser = false
    @State private var showCameraSheet = false
    @State private var showGalleryPicker = false

    // 1h expiry warning (in-line toast)
    @State private var showExpiryWarning = false

    // Long-press action sheet (reactions + edit/delete)
    @State private var actionSheetMessage: Message? = nil

    // Voice recording
    @StateObject private var voiceRecorder = VoiceRecorder()

    var body: some View {
        VStack(spacing: 0) {
            // Slide-in unlock toast at the very top
            unlockToastView

            // Expiry warning banner
            if showExpiryWarning {
                HStack(spacing: 8) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 12))
                    Text("Less than 1 hour left to chat!")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(AppTheme.warning)
                        .shadow(color: AppTheme.warning.opacity(0.4), radius: 10, x: 0, y: 4)
                )
                .padding(.vertical, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Lock banner (only when I sent ice-breaker and am waiting)
            chatBannerSection

            // Messages + typing
            messageListSection

            // Ice-breaker cards (only when chat is empty and no one has messaged)
            icebreakerView

            // Text input
            inputBarSection
        }
        .appBackground()
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ChatHeaderPrincipal(match: match, chatVM: chatVM)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                ChatTrailingButtons(
                    match: match,
                    callsUnlocked: chatVM.match?.callsUnlocked ?? false,
                    showMoreMenu: $showMoreMenu,
                    showUnmatchAlert: $showUnmatchAlert,
                    showBlockAlert: $showBlockAlert,
                    showReportSheet: $showReportSheet
                )
            }
        }
        .onAppear {
            chatVM.inboxViewModel = inboxVM
            chatVM.loadMessages(for: match)
            chatVM.markUnreadMessagesAsRead()
        }
        .onDisappear {
            // Resume push notifications for this chat (enter_chat suppresses
            // them server-side for up to an hour otherwise)
            chatVM.leaveChat()
        }
        .onChange(of: chatVM.chatUnlocked) { _, unlocked in
            if unlocked {
                withAnimation(.spring(response: 0.4)) {
                    showUnlockToast = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation { showUnlockToast = false }
                }
            }
        }
        // Unmatch confirmation
        .alert("Unmatch with \(match.otherUser.displayName)?", isPresented: $showUnmatchAlert) {
            Button("Unmatch", role: .destructive) { chatVM.unmatch(); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll both lose this conversation and won't be able to rematch.")
        }
        // Block confirmation
        .alert("Block \(match.otherUser.displayName)?", isPresented: $showBlockAlert) {
            Button("Block", role: .destructive) { chatVM.block(); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They won't be able to message you or see your profile.")
        }
        // Report sheet
        .sheet(isPresented: $showReportSheet) {
            ReportSheet(userName: match.otherUser.displayName, userId: match.otherUser.id, isPresented: $showReportSheet)
        }
        // Attachment chooser: Camera or Gallery
        .confirmationDialog("Send a photo", isPresented: $showAttachmentChooser, titleVisibility: .visible) {
            Button("Take a live photo") {
                showCameraSheet = true
            }
            Button("Choose from gallery") {
                showGalleryPicker = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showCameraSheet) {
            CameraGalleryPicker(sourceType: .camera) { url in
                handlePickedImage(url)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showGalleryPicker) {
            CameraGalleryPicker(sourceType: .photoLibrary) { url in
                handlePickedImage(url)
            }
            .ignoresSafeArea()
        }
        // Image size error alert
        .alert("Photo error", isPresented: Binding(
            get: { photoErrorMessage != nil },
            set: { if !$0 { photoErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(photoErrorMessage ?? "")
        }
        // Fullscreen image viewer
        .fullScreenCover(isPresented: Binding(
            get: { viewerImageUrl != nil },
            set: { if !$0 { viewerImageUrl = nil } }
        )) {
            ChatImageViewer(urlString: viewerImageUrl ?? "") {
                viewerImageUrl = nil
            }
        }
        // Long-press action sheet (reactions + edit/delete)
        .sheet(item: $actionSheetMessage) { msg in
            MessageActionSheet(
                message: msg,
                onReact: { emoji in
                    chatVM.toggleReaction(msg, emoji: emoji)
                    actionSheetMessage = nil
                },
                onEdit: {
                    chatVM.startEdit(msg)
                    actionSheetMessage = nil
                },
                onDelete: {
                    chatVM.deleteMessage(msg)
                    actionSheetMessage = nil
                },
                onCancel: { actionSheetMessage = nil }
            )
            .presentationDetents([.height(msg.isFromMe ? 200 : 110)])
            .presentationDragIndicator(.visible)
        }
        // 1-hour expiry warning — fires once per match per session
        .task(id: match.id) {
            guard let expiresAt = match.expiresAt else { return }
            let remaining = expiresAt.timeIntervalSinceNow
            if remaining > 0 && remaining <= 60 * 60 {
                let key = "chat_1h_warned_\(match.id)"
                if !ChatExpiryWarnings.shared.shown.contains(key) {
                    ChatExpiryWarnings.shared.shown.insert(key)
                    showExpiryWarning = true
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    showExpiryWarning = false
                }
            }
        }
    }

    // MARK: - Unlock Toast

    @ViewBuilder
    private var unlockToastView: some View {
        if showUnlockToast {
            HStack(spacing: 8) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 12))
                Text(localization.t("chat.chatUnlocked"))
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(AppTheme.success)
                    .shadow(color: AppTheme.success.opacity(0.4), radius: 10, x: 0, y: 4)
            )
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
            .padding(.top, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Banner Section (only when I sent first and am waiting)

    @ViewBuilder
    private var chatBannerSection: some View {
        if chatVM.isLockedForMe {
            ChatLockBanner(chatVM: chatVM, otherUserName: match.otherUser.displayName)
        }
    }

    // MARK: - Message List

    private var messageListSection: some View {
        ChatMessageList(chatVM: chatVM, match: match, viewerImageUrl: $viewerImageUrl, actionSheetMessage: $actionSheetMessage)
    }

    // MARK: - Icebreaker

    @ViewBuilder
    private var icebreakerView: some View {
        if match.status == .pendingFirstMessage && !chatVM.hasMessages {
            ChatIcebreakerSection(chatVM: chatVM)
        }
    }

    // MARK: - Input Bar

    private var inputBarSection: some View {
        VStack(spacing: 0) {
            if voiceRecorder.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                        .opacity(0.85)
                    Text("Recording… \(formatRecordingTime(voiceRecorder.seconds))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Button("Cancel") { voiceRecorder.cancel() }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppTheme.rose)
            }
            if chatVM.editingMessageId != nil {
                HStack(spacing: 8) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.rose)
                    Text("Editing message")
                        .font(.system(size: 12))
                        .foregroundColor(colors.textPrimary)
                    Spacer()
                    Button("Cancel") { chatVM.cancelEdit() }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.rose)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppTheme.rose.opacity(0.06))
            }
            ChatInputBar(
                chatVM: chatVM,
                isInputFocused: $isInputFocused,
                onAttachmentTap: { showAttachmentChooser = true },
                recorder: voiceRecorder,
                onVoiceFinished: { url, duration in
                    chatVM.sendVoice(localUrl: url.absoluteString, durationSeconds: duration)
                }
            )
        }
    }

    private func formatRecordingTime(_ s: Int) -> String {
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }

    private func handlePickedImage(_ url: URL) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        if size > 15 * 1024 * 1024 {
            photoErrorMessage = "Image must be under 15MB"
            try? FileManager.default.removeItem(at: url)
            return
        }
        chatVM.sendImage(localUrl: url.absoluteString)
    }
}

// MARK: - Toolbar Principal

private struct ChatHeaderPrincipal: View {
    let match: Match
    @ObservedObject var chatVM: ChatViewModel
    @Environment(\.adaptiveColors) private var colors

    var body: some View {
        HStack(spacing: 10) {
            ProfileAvatar(
                url: match.otherUser.primaryPhoto?.url,
                name: match.otherUser.displayName,
                size: 36,
                isOnline: match.otherUser.isOnline
            )

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(match.otherUser.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                    if match.otherUser.age > 0 {
                        Text("\(match.otherUser.age)")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(colors.textSecondary)
                    }
                }
                onlineStatus
            }
        }
    }

    private var onlineStatus: some View {
        HStack(spacing: 4) {
            if match.otherUser.isOnline {
                Circle()
                    .fill(AppTheme.success)
                    .frame(width: 6, height: 6)
                Text(LocalizationManager.shared.t("chat.online"))
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.success)
            } else {
                Text(match.otherUser.lastActive?.timeAgoShort ?? "")
                    .font(.system(size: 11))
                    .foregroundColor(colors.textMuted)
            }
        }
    }
}

// MARK: - Toolbar Trailing (video, voice, "..." menu)

private struct ChatTrailingButtons: View {
    let match: Match
    let callsUnlocked: Bool
    @Binding var showMoreMenu: Bool
    @Binding var showUnmatchAlert: Bool
    @Binding var showBlockAlert: Bool
    @Binding var showReportSheet: Bool
    @Environment(\.adaptiveColors) private var colors
    @State private var comingSoonMessage: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            // Video call
            Button {
                comingSoonMessage = "📹 Video calls coming soon"
            } label: {
                Image(systemName: "video.fill")
                    .font(.system(size: 17))
                    .foregroundColor(callsUnlocked ? colors.textPrimary : colors.textMuted.opacity(0.35))
            }
            .disabled(!callsUnlocked)

            // Voice call
            Button {
                comingSoonMessage = "📞 Voice calls coming soon"
            } label: {
                Image(systemName: "phone.fill")
                    .font(.system(size: 16))
                    .foregroundColor(callsUnlocked ? colors.textPrimary : colors.textMuted.opacity(0.35))
            }
            .disabled(!callsUnlocked)

            // "..." overflow menu
            Menu {
                Button {
                    showUnmatchAlert = true
                } label: {
                    Label("Unmatch", systemImage: "heart.slash")
                }

                Button {
                    showBlockAlert = true
                } label: {
                    Label("Block", systemImage: "nosign")
                }

                Button {
                    showReportSheet = true
                } label: {
                    Label("Report", systemImage: "flag")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                    .frame(width: 28, height: 28)
            }
        }
        .alert("Coming soon", isPresented: Binding(
            get: { comingSoonMessage != nil },
            set: { if !$0 { comingSoonMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(comingSoonMessage ?? "")
        }
    }
}

// MARK: - Lock Banner (only while waiting for their reply after I sent the ice-breaker)

private struct ChatLockBanner: View {
    @ObservedObject var chatVM: ChatViewModel
    let otherUserName: String
    @Environment(\.adaptiveColors) private var colors

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.rose.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "lock.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AppTheme.rose)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Waiting for reply...")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.rose)
                Text("You can send another message once \(otherUserName) replies.")
                    .font(.system(size: 11))
                    .foregroundColor(colors.textMuted)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppTheme.rose.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppTheme.rose.opacity(0.15), lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }
}

// MARK: - Message List

private struct ChatMessageList: View {
    @ObservedObject var chatVM: ChatViewModel
    let match: Match
    @Binding var viewerImageUrl: String?
    @Binding var actionSheetMessage: Message?
    @Environment(\.adaptiveColors) private var colors
    @State private var showScrollToBottom = false

    private var otherUserName: String { match.otherUser.displayName }
    private var otherUserAvatarURL: String? { match.otherUser.primaryPhoto?.url }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    matchAnnouncementView

                    // First-message deadline + one-time 24h extend
                    if let live = chatVM.match ?? Optional(match),
                       live.status == .pendingFirstMessage, live.showCountdown {
                        expiryExtendBanner(for: live)
                    }

                    if chatVM.match?.hasFirstMessage == false {
                        systemMessageText(LocalizationManager.shared.t("chat.matchedSendMessage"))
                    }

                    ForEach(groupedMessages, id: \.date) { group in
                        dateSectionHeader(group.dateLabel)

                        ForEach(group.messages) { msg in
                            ChatMessageBubble(
                                message: msg,
                                otherUserName: otherUserName,
                                otherUserAvatarURL: otherUserAvatarURL,
                                onImageTap: { url in viewerImageUrl = url },
                                onLongPress: { m in actionSheetMessage = m }
                            )
                            .id(msg.id)
                        }
                    }

                    if chatVM.isLockedForMe {
                        systemMessageText(
                            LocalizationManager.shared
                                .t("chat.waitingForReplyFrom")
                                .replacingOccurrences(of: "%@", with: otherUserName)
                        )
                    }

                    if chatVM.isOtherTyping {
                        ChatTypingIndicator(
                            otherUserName: otherUserName,
                            avatarURL: otherUserAvatarURL
                        )
                        .id("typing")
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("bottom-anchor")
                        .onAppear  { showScrollToBottom = false }
                        .onDisappear { showScrollToBottom = true }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .overlay(alignment: .bottom) {
                if showScrollToBottom {
                    newMessageButton(proxy: proxy)
                }
            }
            .onChange(of: chatVM.messages.count) { _, _ in
                let target = chatVM.messages.last?.id ?? "typing"
                withAnimation {
                    proxy.scrollTo(target, anchor: .bottom)
                }
            }
        }
    }

    // MARK: "New message ↓" pill button

    private func newMessageButton(proxy: ScrollViewProxy) -> some View {
        Button {
            let target = chatVM.messages.last?.id ?? "bottom-anchor"
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(target, anchor: .bottom)
            }
        } label: {
            HStack(spacing: 6) {
                Text("New message")
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(AppTheme.rose)
                    .shadow(color: AppTheme.rose.opacity(0.4), radius: 8, x: 0, y: 4)
            )
        }
        .padding(.bottom, 10)
        .transition(.opacity.combined(with: .scale(scale: 0.85)))
        .animation(.spring(response: 0.3), value: showScrollToBottom)
    }

    // MARK: - Date Grouping

    private struct MessageGroup: Hashable {
        let date: String
        let dateLabel: String
        let messages: [Message]
    }

    private var groupedMessages: [MessageGroup] {
        let keyFormatter = DateFormatter()
        keyFormatter.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar.current
        var groups: [String: [Message]] = [:]
        var order: [String] = []

        for msg in chatVM.messages {
            let key = keyFormatter.string(from: msg.createdAt)
            if groups[key] == nil {
                order.append(key)
                groups[key] = []
            }
            groups[key]?.append(msg)
        }

        return order.compactMap { key -> MessageGroup? in
            guard let msgs = groups[key], let first = msgs.first else { return nil }
            let label: String
            if calendar.isDateInToday(first.createdAt) {
                label = "Today"
            } else if calendar.isDateInYesterday(first.createdAt) {
                label = "Yesterday"
            } else {
                let fmt = DateFormatter()
                fmt.dateFormat = "EEEE, MMM d"
                label = fmt.string(from: first.createdAt)
            }
            return MessageGroup(date: key, dateLabel: label, messages: msgs)
        }
    }

    // MARK: - Section Header

    private func dateSectionHeader(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(colors.textMuted)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(colors.border))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }

    // MARK: - Match Announcement

    private var matchAnnouncementView: some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        let dateString = formatter.string(from: match.matchedAt)

        return HStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .font(.system(size: 10))
                .foregroundColor(AppTheme.rose.opacity(0.7))
            Text("You matched with \(otherUserName) on \(dateString)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colors.textMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(colors.surfaceMedium)
                .overlay(Capsule().stroke(colors.border, lineWidth: 0.5))
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - First-message deadline banner + one-time 24h extend

    private func expiryExtendBanner(for live: Match) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let remaining = max(0, (live.expiresAt ?? context.date).timeIntervalSince(context.date))
            let hours = Int(remaining) / 3600
            let minutes = (Int(remaining) % 3600) / 60
            let timeLabel = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"

            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.saffron)
                Text("\(timeLabel) left for the first message")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colors.textPrimary)
                Spacer()
                if live.extendedOnce == true {
                    Text("Extended ✓")
                        .font(.system(size: 12))
                        .foregroundColor(colors.textMuted)
                } else {
                    Button {
                        chatVM.extendMatch()
                    } label: {
                        Text(chatVM.isExtending ? "Extending…" : "Extend 24h")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.saffron)
                    }
                    .disabled(chatVM.isExtending)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.saffron.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppTheme.saffron.opacity(0.35), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 16)
        }
    }

    // MARK: - System Message

    private func systemMessageText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(colors.textMuted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 30)
            .padding(.vertical, 8)
    }
}

// MARK: - Message Bubble
// Sent: rose color, right-aligned, no avatar.
// Received: gray surfaceMedium, left-aligned, 32pt avatar beside it.

private struct ChatMessageBubble: View {
    let message: Message
    let otherUserName: String
    let otherUserAvatarURL: String?
    var onImageTap: (String) -> Void = { _ in }
    var onLongPress: (Message) -> Void = { _ in }

    @Environment(\.adaptiveColors) private var colors
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    private var isEdited: Bool {
        message.msgType == .text && message.content.contains("[edited]")
    }

    private var displayContent: String {
        if isEdited {
            var s = message.content
            if s.hasSuffix(" [edited]") { s = String(s.dropLast(" [edited]".count)) }
            else if s.hasSuffix("[edited]") { s = String(s.dropLast("[edited]".count)) }
            return s.trimmingCharacters(in: .whitespaces)
        }
        return message.content
    }

    private let bubbleRadius: CGFloat = 18
    private let tailRadius: CGFloat  = 4

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.isFromMe {
                Spacer(minLength: 60)
                sentContent
            } else {
                // Avatar (32pt)
                ProfileAvatar(
                    url: otherUserAvatarURL,
                    name: otherUserName,
                    size: 32
                )

                receivedContent
                Spacer(minLength: 60)
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .scaleEffect(appeared ? 1 : 0.97)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }

    // MARK: Sent bubble (rose, right)

    private var sentContent: some View {
        VStack(alignment: .trailing, spacing: 4) {
            icebreakerLabel

            ZStack(alignment: .bottomLeading) {
                Group {
                    if isPhoto {
                        photoBubble
                    } else if isVoice {
                        voiceBubble
                    } else if message.msgType != .system {
                        Text(displayContent)
                            .font(.system(size: 15))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(sentBubble)
                            .shadow(color: AppTheme.rose.opacity(0.2), radius: 8, x: 0, y: 3)
                    } else {
                        systemText
                    }
                }
                .onLongPressGesture(minimumDuration: 0.35) { onLongPress(message) }

                reactionChip
                    .offset(x: -6, y: 8)
            }

            timestampRow
        }
    }

    // MARK: Received bubble (gray, left)

    private var receivedContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            icebreakerLabel

            ZStack(alignment: .bottomTrailing) {
                Group {
                    if isPhoto {
                        photoBubble
                    } else if isVoice {
                        voiceBubble
                    } else if message.msgType != .system {
                        Text(displayContent)
                            .font(.system(size: 15))
                            .foregroundColor(colors.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(receivedBubble)
                            .shadow(color: colors.cardShadowColor.opacity(0.5), radius: 5, x: 0, y: 2)
                    } else {
                        systemText
                    }
                }
                .onLongPressGesture(minimumDuration: 0.35) { onLongPress(message) }

                reactionChip
                    .offset(x: 6, y: 8)
            }

            timestampRow
        }
    }

    @ViewBuilder
    private var reactionChip: some View {
        if let r = message.reaction {
            Text(r)
                .font(.system(size: 12))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(colors.cardDark)
                        .overlay(Capsule().stroke(colors.border, lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
                )
        }
    }

    private var isPhoto: Bool {
        message.msgType == .photo && (message.mediaUrl?.isEmpty == false)
    }

    private var isVoice: Bool {
        message.msgType == .voice && (message.mediaUrl?.isEmpty == false)
    }

    @ViewBuilder
    private var voiceBubble: some View {
        VoicePlaybackBubble(
            audioUrl: message.mediaUrl ?? "",
            durationSeconds: message.durationSeconds,
            isFromMe: message.isFromMe
        )
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(message.isFromMe ? AnyShapeStyle(AppTheme.roseGradient) : AnyShapeStyle(colors.surfaceMedium))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var photoBubble: some View {
        Button {
            if let url = message.mediaUrl { onImageTap(url) }
        } label: {
            AsyncImage(url: URL(string: message.mediaUrl ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Image(systemName: "photo")
                        .font(.system(size: 32))
                        .foregroundColor(colors.textMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(colors.surfaceMedium)
                default:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(colors.surfaceMedium)
                }
            }
            .frame(maxWidth: 240, maxHeight: 320)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    // MARK: Bubble shapes

    /// Sent bubble: 18dp radius on all corners except bottom-right uses 4dp (tail)
    private var sentBubble: some View {
        SentBubbleShape(mainRadius: bubbleRadius, tailRadius: tailRadius)
            .fill(AppTheme.roseGradient)
    }

    /// Received bubble: 18dp radius on all corners except bottom-left uses 4dp (tail)
    private var receivedBubble: some View {
        ReceivedBubbleShape(mainRadius: bubbleRadius, tailRadius: tailRadius)
            .fill(colors.surfaceMedium)
            .overlay(
                ReceivedBubbleShape(mainRadius: bubbleRadius, tailRadius: tailRadius)
                    .stroke(colors.border, lineWidth: 0.5)
            )
    }

    // MARK: Sub-views

    @ViewBuilder
    private var icebreakerLabel: some View {
        if message.msgType == .icebreaker {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                Text("Icebreaker")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(AppTheme.gold)
        }
    }

    private var systemText: some View {
        Text(message.content)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(colors.textMuted)
            .italic()
    }

    private var timestampRow: some View {
        HStack(spacing: 4) {
            if isEdited {
                Text("edited")
                    .font(.system(size: 10))
                    .italic()
                    .foregroundColor(colors.textMuted)
            }
            Text(message.createdAt.messageTime)
                .font(.system(size: 10))
                .foregroundColor(colors.textMuted)

            if message.isFromMe {
                readReceiptIcon
            }
        }
    }

    // MARK: Read receipt

    private var readColor: Color {
        colorScheme == .dark ? .white : Color(hex: "3478F6")
    }

    @ViewBuilder
    private var readReceiptIcon: some View {
        switch message.status {
        case .sending:
            Image(systemName: "clock")
                .font(.system(size: 10))
                .foregroundColor(colors.textMuted)
        case .sent:
            // Single checkmark
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(colors.textMuted)
        case .delivered:
            // Double gray checkmarks
            doubleCheck(color: colors.textMuted)
        case .read:
            // Double blue checkmarks
            doubleCheck(color: readColor)
        }
    }

    private func doubleCheck(color: Color) -> some View {
        ZStack(alignment: .leading) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(color)
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(color)
                .offset(x: 5)
        }
        .frame(width: 19)
    }
}

// MARK: - Sent Bubble Shape (tail on bottom-right)

private struct SentBubbleShape: Shape {
    let mainRadius: CGFloat
    let tailRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tl = mainRadius
        let tr = mainRadius
        let bl = mainRadius
        let br = tailRadius  // tail side

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                    radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
                    radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
                    radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
                    radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

// MARK: - Received Bubble Shape (tail on bottom-left)

private struct ReceivedBubbleShape: Shape {
    let mainRadius: CGFloat
    let tailRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tl = mainRadius
        let tr = mainRadius
        let bl = tailRadius  // tail side
        let br = mainRadius

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                    radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
                    radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
                    radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
                    radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

// MARK: - Typing Indicator (dots bubble + avatar on left)

private struct ChatTypingIndicator: View {
    let otherUserName: String
    let avatarURL: String?
    @Environment(\.adaptiveColors) private var colors
    @State private var dotScale: [CGFloat] = [1, 1, 1]
    @State private var dotOpacity: [Double] = [0.4, 0.4, 0.4]

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ProfileAvatar(url: avatarURL, name: otherUserName, size: 32)

            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(colors.textMuted)
                        .frame(width: 7, height: 7)
                        .scaleEffect(dotScale[i])
                        .opacity(dotOpacity[i])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                ReceivedBubbleShape(mainRadius: 18, tailRadius: 4)
                    .fill(colors.surfaceMedium)
            )
            .overlay(
                ReceivedBubbleShape(mainRadius: 18, tailRadius: 4)
                    .stroke(colors.border, lineWidth: 0.5)
            )

            Spacer()
        }
        .onAppear { animateDots() }
    }

    private func animateDots() {
        for i in 0..<3 {
            withAnimation(
                .easeInOut(duration: 0.6)
                .repeatForever(autoreverses: true)
                .delay(Double(i) * 0.18)
            ) {
                dotScale[i]   = 1.4
                dotOpacity[i] = 1.0
            }
        }
    }
}

// MARK: - Icebreaker Section
// Shows 2-3 random prompts. Dice button to shuffle. Tap → send.

private struct ChatIcebreakerSection: View {
    @ObservedObject var chatVM: ChatViewModel
    @Environment(\.adaptiveColors) private var colors

    @State private var visiblePrompts: [IceBreakerPrompt] = IceBreakerPrompts.random(count: 3)

    /// Server suggestions (Sindhi-flavored pool) mapped into prompt cards
    private var serverPrompts: [IceBreakerPrompt] {
        chatVM.serverIcebreakers.enumerated().map { i, q in
            IceBreakerPrompt(id: 1000 + i, text: q, category: .sindhi)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            icebreakerHeader
            promptCards
        }
        .padding(.vertical, 12)
        .onChange(of: chatVM.serverIcebreakers) { _, fresh in
            // Prefer the server's Sindhi-flavored suggestions when they arrive
            if !fresh.isEmpty {
                visiblePrompts = serverPrompts
            }
        }
    }

    // MARK: Header row

    private var icebreakerHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundColor(AppTheme.rose)
            Text(LocalizationManager.shared.t("chat.breakTheIce"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.rose)

            Spacer()

            // Dice shuffle button — draws from the union of server + local pools
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    visiblePrompts = Array((serverPrompts + IceBreakerPrompts.getAll()).shuffled().prefix(3))
                }
            } label: {
                Image(systemName: "dice.fill")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.rose)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(AppTheme.rose.opacity(0.1))
                            .overlay(Circle().stroke(AppTheme.rose.opacity(0.2), lineWidth: 1))
                    )
            }
        }
        .padding(.horizontal)
    }

    // MARK: Prompt cards

    private var promptCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(visiblePrompts) { prompt in
                    Button {
                        chatVM.sendIcebreaker(prompt.text)
                    } label: {
                        IceBreakerPromptCard(prompt: prompt)
                    }
                    .buttonStyle(IcebreakerButtonStyle())
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Icebreaker Prompt Card

private struct IceBreakerPromptCard: View {
    let prompt: IceBreakerPrompt
    @Environment(\.adaptiveColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Category row: emoji + category name
            HStack(spacing: 5) {
                Text(prompt.category.emoji)
                    .font(.system(size: 12))
                Text(prompt.category.displayName.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
            }
            .foregroundColor(AppTheme.rose)

            // Prompt text
            Text(prompt.text)
                .font(.system(size: 13))
                .foregroundColor(colors.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
        }
        .padding(14)
        .frame(width: 200, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppTheme.rose.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [AppTheme.rose.opacity(0.3), AppTheme.rose.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: AppTheme.rose.opacity(0.1), radius: 8, x: 0, y: 4)
        )
    }
}

// MARK: - Icebreaker Button Style

private struct IcebreakerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Input Bar

private struct ChatInputBar: View {
    @ObservedObject var chatVM: ChatViewModel
    var isInputFocused: FocusState<Bool>.Binding
    var onAttachmentTap: () -> Void
    @ObservedObject var recorder: VoiceRecorder
    var onVoiceFinished: (URL, Int) -> Void
    @Environment(\.adaptiveColors) private var colors
    @State private var chatPhotoItem: PhotosPickerItem?

    var body: some View {
        if chatVM.inputDisabled {
            inputBarContainer { disabledContent }
        } else {
            inputBarContainer { activeContent }
        }
    }

    private func inputBarContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Rectangle().fill(colors.surfaceDark.opacity(0.5)))
                    .overlay(alignment: .top) {
                        Divider().foregroundColor(colors.border)
                    }
                    .ignoresSafeArea()
            )
    }

    private var disabledContent: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 16))
                .foregroundColor(colors.textMuted)

            Text(chatVM.inputPlaceholder)
                .font(.system(size: 15))
                .foregroundColor(colors.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(colors.surfaceMedium)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(colors.border, lineWidth: 0.5)
                )
        )
    }

    private var activeContent: some View {
        HStack(spacing: 10) {
            Button(action: onAttachmentTap) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 20))
                    .foregroundColor(colors.textMuted)
            }
            .disabled(chatVM.isLockedForMe)

            HStack {
                TextField(chatVM.inputPlaceholder, text: $chatVM.messageText, axis: .vertical)
                    .font(.system(size: 15))
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1...4)
                    .focused(isInputFocused)

                Button {} label: {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 20))
                        .foregroundColor(colors.textMuted)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(colors.surfaceMedium)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(colors.border, lineWidth: 0.5)
                    )
            )

            photoAttachButton

            if chatVM.messageText.isEmpty {
                MicHoldButton(
                    isRecording: recorder.isRecording,
                    onStart: {
                        Task {
                            let ok = await recorder.startRecording()
                            if !ok {
                                // permission/setup failure handled silently for now
                            }
                        }
                    },
                    onStop: { cancel in
                        if cancel {
                            recorder.cancel()
                            return
                        }
                        if let result = recorder.stopRecording() {
                            onVoiceFinished(result.url, result.duration)
                        }
                    }
                )
            } else {
                sendButton
            }
        }
    }

    private var sendButton: some View {
        Button {
            chatVM.sendMessage()
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(AppTheme.roseGradient)
                .clipShape(Circle())
        }
    }

    private var photoAttachButton: some View {
        PhotosPicker(selection: $chatPhotoItem, matching: .images) {
            Image(systemName: "photo")
                .font(.system(size: 20))
                .foregroundColor(colors.textMuted)
        }
        .onChange(of: chatPhotoItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let compressed = image.compressedForUpload() ?? image.jpegData(compressionQuality: 0.8) {
                    chatVM.sendPhoto(imageData: compressed)
                }
                chatPhotoItem = nil
            }
        }
    }
}

// MARK: - Report Sheet

private struct ReportSheet: View {
    let userName: String
    let userId: String
    @Binding var isPresented: Bool
    @Environment(\.adaptiveColors) private var colors

    @State private var selectedReason: ReportReason?
    @State private var showConfirmation = false

    enum ReportReason: String, CaseIterable, Identifiable {
        case inappropriateBehavior = "Inappropriate behavior"
        case fakeProfile           = "Fake profile"
        case spam                  = "Spam"
        case underage              = "Underage"
        case other                 = "Other"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                if showConfirmation {
                    confirmationView
                } else {
                    reasonPickerView
                }
            }
            .navigationTitle("Report \(userName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                        .foregroundColor(colors.textSecondary)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: Reason picker

    private var reasonPickerView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Why are you reporting this profile?")
                .font(.system(size: 14))
                .foregroundColor(colors.textSecondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

            ForEach(ReportReason.allCases) { reason in
                Button {
                    selectedReason = reason
                } label: {
                    HStack {
                        Text(reason.rawValue)
                            .font(.system(size: 16))
                            .foregroundColor(colors.textPrimary)
                        Spacer()
                        if selectedReason == reason {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.rose)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }

                Divider()
                    .padding(.leading, 20)
            }

            Spacer()

            Button {
                guard let reason = selectedReason else { return }
                // Map the UI reason to the backend's report reason enum and submit.
                let code: String
                switch reason {
                case .inappropriateBehavior: code = "harassment"
                case .fakeProfile:           code = "fake"
                case .spam:                  code = "spam"
                case .underage:              code = "underage"
                case .other:                 code = "safety"
                }
                Task { try? await APIService.shared.reportUser(userId: userId, reason: code, details: nil) }
                showConfirmation = true
            } label: {
                Text("Submit Report")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(selectedReason == nil ? colors.textMuted : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(selectedReason == nil ? colors.surfaceMedium : AppTheme.rose)
                    )
            }
            .disabled(selectedReason == nil)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: Confirmation

    private var confirmationView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundColor(AppTheme.success)

            VStack(spacing: 8) {
                Text("Report submitted")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                Text("Thank you. We review all reports within 24 hours.")
                    .font(.system(size: 14))
                    .foregroundColor(colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            Button("Done") { isPresented = false }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.rose))
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
        }
    }
}

// MARK: - Camera + Gallery picker (UIImagePickerController wrapper)

struct CameraGalleryPicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onPicked: (URL) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPicked: (URL) -> Void
        init(onPicked: @escaping (URL) -> Void) { self.onPicked = onPicked }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            picker.dismiss(animated: true)
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.85) else { return }
            let tempUrl = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).jpg")
            do {
                try data.write(to: tempUrl)
                onPicked(tempUrl)
            } catch {
                // ignore — could surface an error if needed
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Voice Recorder

@MainActor
final class VoiceRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var seconds = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var startedAt: Date?
    private var fileURL: URL?

    func startRecording() async -> Bool {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { return false }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            return false
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice_\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.record()
            recorder = r
            fileURL = url
            startedAt = Date()
            isRecording = true
            seconds = 0
            startTimer()
            return true
        } catch {
            return false
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startedAt else { return }
                self.seconds = Int(Date().timeIntervalSince(start))
                if self.seconds >= 300 {
                    _ = self.stopRecording()
                }
            }
        }
    }

    @discardableResult
    func stopRecording() -> (url: URL, duration: Int)? {
        guard isRecording else { return nil }
        recorder?.stop()
        timer?.invalidate()
        timer = nil
        let duration = startedAt.map { Int(Date().timeIntervalSince($0)) } ?? 0
        startedAt = nil
        isRecording = false
        seconds = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        guard let url = fileURL, duration >= 1 else {
            if let u = fileURL { try? FileManager.default.removeItem(at: u) }
            fileURL = nil
            return nil
        }
        let result = (url, duration)
        fileURL = nil
        recorder = nil
        return result
    }

    func cancel() {
        guard isRecording else { return }
        recorder?.stop()
        timer?.invalidate()
        timer = nil
        if let u = fileURL { try? FileManager.default.removeItem(at: u) }
        fileURL = nil
        recorder = nil
        startedAt = nil
        isRecording = false
        seconds = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

// MARK: - Mic hold-to-record button

private struct MicHoldButton: View {
    let isRecording: Bool
    let onStart: () -> Void
    let onStop: (Bool) -> Void
    @Environment(\.adaptiveColors) private var colors
    @State private var pressing = false

    var body: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 20))
            .foregroundColor(isRecording ? .white : colors.textMuted)
            .frame(width: 44, height: 44)
            .background(
                Circle().fill(isRecording ? AppTheme.rose : Color.clear)
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pressing {
                            pressing = true
                            onStart()
                        }
                    }
                    .onEnded { value in
                        let cancel = abs(value.translation.width) > 80 || value.translation.height < -80
                        pressing = false
                        onStop(cancel)
                    }
            )
    }
}

// MARK: - Voice playback bubble (play/pause + stylized waveform + duration)

private let voiceBarHeights: [Double] = [
    0.55, 0.78, 0.42, 0.92, 0.65, 0.38, 0.85, 0.58, 0.72, 0.46,
    0.88, 0.51, 0.66, 0.81, 0.43, 0.74, 0.59, 0.95, 0.62, 0.49
]

struct VoicePlaybackBubble: View {
    let audioUrl: String
    let durationSeconds: Int
    let isFromMe: Bool

    @State private var isPlaying = false
    @State private var progress: Double = 0
    @State private var player: AVAudioPlayer?
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggle) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(isFromMe ? Color.white.opacity(0.25) : AppTheme.rose)
                    )
            }
            HStack(spacing: 2) {
                ForEach(voiceBarHeights.indices, id: \.self) { i in
                    let filled = Double(i) / Double(voiceBarHeights.count) <= progress
                    Capsule()
                        .fill(barColor(filled: filled))
                        .frame(width: 3, height: 24 * voiceBarHeights[i])
                }
            }
            Text(formatted)
                .font(.system(size: 11))
                .foregroundColor(isFromMe ? .white.opacity(0.85) : .gray)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 200)
        .onDisappear {
            player?.stop()
            timer?.invalidate()
            timer = nil
        }
    }

    private func barColor(filled: Bool) -> Color {
        if isFromMe {
            return filled ? .white : .white.opacity(0.4)
        } else {
            return filled ? AppTheme.rose : Color(white: 0.8)
        }
    }

    private var formatted: String {
        let m = durationSeconds / 60
        let s = durationSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func toggle() {
        if let p = player {
            if p.isPlaying {
                p.pause()
                isPlaying = false
            } else {
                p.play()
                isPlaying = true
                startTimer()
            }
            return
        }
        let url = URL(string: audioUrl) ?? URL(fileURLWithPath: audioUrl)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            p.play()
            player = p
            isPlaying = true
            startTimer()
        } catch {
            // Silent fail; consider toast in future
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            guard let p = player else { return }
            if p.duration > 0 {
                progress = p.currentTime / p.duration
            }
            if !p.isPlaying {
                isPlaying = false
                if p.currentTime >= p.duration {
                    progress = 0
                }
                timer?.invalidate()
                timer = nil
            }
        }
    }
}

// MARK: - Message action sheet (reactions + edit/delete)

private struct MessageActionSheet: View {
    let message: Message
    let onReact: (String) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void
    @Environment(\.adaptiveColors) private var colors

    var body: some View {
        VStack(spacing: 16) {
            // Reactions row
            HStack(spacing: 8) {
                ForEach(Message.allowedReactions, id: \.self) { emoji in
                    let selected = message.reaction == emoji
                    Button { onReact(emoji) } label: {
                        Text(emoji)
                            .font(.system(size: 26))
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(selected ? AppTheme.rose.opacity(0.15) : Color.clear)
                            )
                    }
                }
            }
            .padding(.top, 8)

            // Edit/delete actions (own messages only)
            if message.isFromMe {
                Divider()
                if message.msgType == .text {
                    Button {
                        onEdit()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                    }
                    .foregroundColor(colors.textPrimary)
                }
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                }
            }

            Spacer(minLength: 0)
        }
        .presentationBackground(colors.cardDark)
    }
}

// MARK: - Expiry warning de-dup (process-wide)

@MainActor
final class ChatExpiryWarnings {
    static let shared = ChatExpiryWarnings()
    var shown: Set<String> = []
    private init() {}
}

// MARK: - Fullscreen Image Viewer

private struct ChatImageViewer: View {
    let urlString: String
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
                .onTapGesture { onClose() }

            AsyncImage(url: URL(string: urlString)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .failure:
                    Image(systemName: "photo")
                        .font(.system(size: 48))
                        .foregroundColor(.white.opacity(0.6))
                default:
                    ProgressView().tint(.white)
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 16)
                }
                Spacer()
            }
        }
    }
}
