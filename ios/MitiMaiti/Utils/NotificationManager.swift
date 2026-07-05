import SwiftUI
import UserNotifications

// MARK: - Notification Type

enum NotificationType: String, Codable, CaseIterable {
    case match, like, message, family, familySuggestion = "family_suggestion"
    case expiry, system, profileView = "profile_view", icebreaker, feature

    var icon: String {
        switch self {
        case .match: return "heart.circle.fill"
        case .like: return "heart.fill"
        case .message: return "message.fill"
        case .family, .familySuggestion: return "person.3.fill"
        case .expiry: return "clock.fill"
        case .system: return "bell.fill"
        case .profileView: return "eye.fill"
        case .icebreaker: return "sparkles"
        case .feature: return "star.fill"
        }
    }

    var color: Color {
        switch self {
        case .match: return AppTheme.rose
        case .like: return AppTheme.rose
        case .message: return AppTheme.info
        case .family, .familySuggestion: return AppTheme.gold
        case .expiry: return AppTheme.warning
        case .system: return AppTheme.textSecondary
        case .profileView: return AppTheme.info
        case .icebreaker: return AppTheme.gold
        case .feature: return AppTheme.success
        }
    }

    /// The tab index this notification type should navigate to
    var destinationTab: Int? {
        switch self {
        case .match: return 2       // Matches tab (chat)
        case .like: return 1        // Liked You / Inbox tab
        case .message: return 2     // Matches tab (chat)
        case .family, .familySuggestion: return nil // Family module removed
        case .expiry: return 2      // Matches tab
        case .profileView: return 4 // Profile tab
        case .icebreaker: return 2  // Matches tab (chat)
        case .system, .feature: return nil // No navigation
        }
    }

    /// The settings key prefix for this notification type
    var settingsKey: String {
        switch self {
        case .match: return "matches"
        case .like: return "likes"
        case .message: return "messages"
        case .family, .familySuggestion: return "family"
        case .expiry: return "expiry"
        case .system: return "safety"
        case .profileView: return "likes"
        case .icebreaker: return "dailyPrompt"
        case .feature: return "newFeatures"
        }
    }
}

// MARK: - App Notification Model

struct AppNotification: Identifiable, Codable {
    let id: String
    let type: NotificationType
    let title: String
    let body: String
    let createdAt: Date
    var isRead: Bool
    var actionData: String?  // e.g., matchId or userId for navigation

    init(
        id: String = UUID().uuidString,
        type: NotificationType,
        title: String,
        body: String,
        createdAt: Date = Date(),
        isRead: Bool = false,
        actionData: String? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.isRead = isRead
        self.actionData = actionData
    }
}

// MARK: - Notification Settings

struct NotificationSettings: Codable {
    var matches: Bool = true
    var messages: Bool = true
    var likes: Bool = true
    var family: Bool = true
    var expiry: Bool = true
    var dailyPrompt: Bool = true
    var newFeatures: Bool = false
    var safety: Bool = true

    func isEnabled(for type: NotificationType) -> Bool {
        switch type {
        case .match: return matches
        case .like: return likes
        case .message: return messages
        case .family, .familySuggestion: return family
        case .expiry: return expiry
        case .system: return safety
        case .profileView: return likes
        case .icebreaker: return dailyPrompt
        case .feature: return newFeatures
        }
    }
}

// MARK: - Notification Manager

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    // MARK: - Published State

    @Published var notifications: [AppNotification] = []
    @Published var settings: NotificationSettings = NotificationSettings()
    @Published var permissionGranted: Bool = false
    @Published var selectedTab: Int = 0  // For navigation from notifications

    // MARK: - Constants

    private static let storageKey = "mm_notifications"
    private static let settingsKey = "mm_notification_settings"
    private static let maxNotifications = 50
    private static let maxAge: TimeInterval = 30 * 24 * 60 * 60 // 30 days

    // MARK: - Computed Properties

    var unreadCount: Int { notifications.filter { !$0.isRead }.count }

    func unreadCount(for types: [NotificationType]) -> Int {
        let typeSet = Set(types)
        return notifications.filter { !$0.isRead && typeSet.contains($0.type) }.count
    }

    var todayNotifications: [AppNotification] {
        notifications.filter { Calendar.current.isDateInToday($0.createdAt) }
    }

    var earlierNotifications: [AppNotification] {
        notifications.filter { !Calendar.current.isDateInToday($0.createdAt) }
    }

    // MARK: - Init

    init() {
        loadSettings()
        loadNotifications()
        checkPermission()
    }

    // MARK: - Permission

    func requestPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            Task { @MainActor in
                self?.permissionGranted = granted
            }
        }
    }

    func checkPermission() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                self?.permissionGranted = settings.authorizationStatus == .authorized
            }
        }
    }

    // MARK: - CRUD Operations

    func addNotification(
        type: NotificationType,
        title: String,
        body: String,
        actionData: String? = nil
    ) {
        // Check if this notification type is enabled in settings
        guard settings.isEnabled(for: type) else { return }

        let notification = AppNotification(
            type: type,
            title: title,
            body: body,
            actionData: actionData
        )
        notifications.insert(notification, at: 0)
        pruneAndSave()

        // Schedule a local push notification if the app is backgrounded
        scheduleLocalPush(title: title, body: body, type: type)
    }

    func markAsRead(_ id: String) {
        if let idx = notifications.firstIndex(where: { $0.id == id }) {
            notifications[idx].isRead = true
            saveNotifications()
        }
    }

    func markAllRead() {
        for i in notifications.indices {
            notifications[i].isRead = true
        }
        saveNotifications()
    }

    func dismiss(_ id: String) {
        notifications.removeAll { $0.id == id }
        saveNotifications()
    }

    func clearAll() {
        notifications.removeAll()
        saveNotifications()
    }

    // MARK: - Navigation

    func handleNotificationTap(_ notification: AppNotification) {
        markAsRead(notification.id)
        if let tab = notification.type.destinationTab {
            selectedTab = tab
        }
    }

    // MARK: - Scheduled Local Notifications

    func scheduleExpiryReminder(matchName: String, expiresAt: Date) {
        guard settings.expiry else { return }

        let center = UNUserNotificationCenter.current()

        // 4-hour reminder
        let fourHoursBefore = expiresAt.addingTimeInterval(-4 * 60 * 60)
        if fourHoursBefore > Date() {
            let content = UNMutableNotificationContent()
            content.title = "Match with \(matchName) expires in 4 hours"
            content.body = "Send a message before it's too late!"
            content.sound = .default
            content.userInfo = ["type": NotificationType.expiry.rawValue]

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: fourHoursBefore.timeIntervalSinceNow,
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: "expiry-4h-\(matchName)-\(expiresAt.timeIntervalSince1970)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }

        // 1-hour reminder
        let oneHourBefore = expiresAt.addingTimeInterval(-1 * 60 * 60)
        if oneHourBefore > Date() {
            let content = UNMutableNotificationContent()
            content.title = "Match with \(matchName) expires in 1 hour!"
            content.body = "Last chance to send a message!"
            content.sound = .default
            content.userInfo = ["type": NotificationType.expiry.rawValue]

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: oneHourBefore.timeIntervalSinceNow,
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: "expiry-1h-\(matchName)-\(expiresAt.timeIntervalSince1970)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }

        // Also add an in-app notification for 4h warning
        if fourHoursBefore <= Date() && oneHourBefore > Date() {
            addNotification(
                type: .expiry,
                title: "Match with \(matchName) expires soon",
                body: "Send a message before it's too late!"
            )
        }
    }

    func scheduleDailyPrompt() {
        guard settings.dailyPrompt else { return }

        let center = UNUserNotificationCenter.current()

        // Remove any existing daily prompt
        center.removePendingNotificationRequests(withIdentifiers: ["daily-prompt"])

        let content = UNMutableNotificationContent()
        content.title = "Check out new profiles today!"
        content.body = "New people are waiting to meet you. Open MitiMaiti and start swiping!"
        content.sound = .default
        content.userInfo = ["type": NotificationType.icebreaker.rawValue]

        // Schedule for 10 AM daily
        var dateComponents = DateComponents()
        dateComponents.hour = 10
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: true
        )
        let request = UNNotificationRequest(
            identifier: "daily-prompt",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    func scheduleWeeklyDigest() {
        guard settings.isEnabled(for: .system) else { return }

        let center = UNUserNotificationCenter.current()

        // Remove any existing weekly digest
        center.removePendingNotificationRequests(withIdentifiers: ["weekly-digest"])

        let content = UNMutableNotificationContent()
        content.title = "Your weekly summary is ready"
        content.body = "See how your profile performed this week!"
        content.sound = .default
        content.userInfo = ["type": NotificationType.system.rawValue]

        // Schedule for Sunday at 6 PM
        var dateComponents = DateComponents()
        dateComponents.weekday = 1 // Sunday
        dateComponents.hour = 18
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: true
        )
        let request = UNNotificationRequest(
            identifier: "weekly-digest",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    // MARK: - Local Push (for background notifications)

    private func scheduleLocalPush(title: String, body: String, type: NotificationType) {
        guard permissionGranted else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["type": type.rawValue]

        // Fire immediately (1 second delay for background delivery)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Persistence

    private func loadNotifications() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else {
            loadSeedNotifications()
            return
        }
        do {
            let decoded = try JSONDecoder().decode([AppNotification].self, from: data)
            // Filter out notifications older than 30 days
            let cutoff = Date().addingTimeInterval(-Self.maxAge)
            notifications = decoded.filter { $0.createdAt > cutoff }
            if notifications.isEmpty {
                loadSeedNotifications()
            }
        } catch {
            loadSeedNotifications()
        }
    }

    private func saveNotifications() {
        do {
            let data = try JSONEncoder().encode(notifications)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            // Silently fail
        }
    }

    private func pruneAndSave() {
        // Prune to max count
        if notifications.count > Self.maxNotifications {
            notifications = Array(notifications.prefix(Self.maxNotifications))
        }
        // Remove old notifications
        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        notifications.removeAll { $0.createdAt < cutoff }
        saveNotifications()
    }

    // MARK: - Settings Persistence

    func loadSettings() {
        guard let data = UserDefaults.standard.data(forKey: Self.settingsKey) else { return }
        if let decoded = try? JSONDecoder().decode(NotificationSettings.self, from: data) {
            settings = decoded
        }
    }

    func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
        // Re-schedule recurring notifications based on updated settings
        scheduleDailyPrompt()
        scheduleWeeklyDigest()
    }

    // MARK: - Initialize (called on app launch)

    func initialize() {
        requestPermission()
        scheduleDailyPrompt()
        scheduleWeeklyDigest()
    }

    // MARK: - FCM token registration
    //
    // To enable real push notifications:
    //   1. Add Firebase iOS SDK (firebase-ios-sdk) to project.yml packages, then:
    //        import FirebaseMessaging
    //   2. Configure GoogleService-Info.plist in the app bundle.
    //   3. In your AppDelegate or @main app, call:
    //        Messaging.messaging().token { token, _ in
    //            if let token { Task { await NotificationManager.shared.registerFcmToken(token) } }
    //        }
    //
    // This method is wired today; only the token source needs Firebase.

    func registerFcmToken(_ token: String) async {
        do {
            try await APIService.shared.registerFcmToken(token, platform: "ios")
        } catch {
            print("[NotificationManager] FCM token registration failed: \(error)")
        }
    }

    // MARK: - Seed Data

    private func loadSeedNotifications() {
        notifications = [
            AppNotification(id: "seed-1", type: .match, title: "New Match!", body: "You and Priya matched! Say hi before the timer runs out.", createdAt: Date().addingTimeInterval(-300)),
            AppNotification(id: "seed-2", type: .like, title: "Someone liked you", body: "Arjun liked your profile. Check Liked You to see!", createdAt: Date().addingTimeInterval(-1800)),
            AppNotification(id: "seed-3", type: .message, title: "New message from Meera", body: "\"I just made the best dal pakwan of my life!\"", createdAt: Date().addingTimeInterval(-3600)),
            AppNotification(id: "seed-5", type: .expiry, title: "Match with Roshni expires in 4h", body: "Send a message before it's too late!", createdAt: Date().addingTimeInterval(-10800), isRead: true),
            AppNotification(id: "seed-6", type: .like, title: "Anika liked your photo", body: "You have a new admirer! Take a look.", createdAt: Date().addingTimeInterval(-14400)),
            AppNotification(id: "seed-8", type: .system, title: "Weekly summary: 47 views, 12 likes", body: "Your profile had a great week! Keep it up.", createdAt: Date().addingTimeInterval(-86400), isRead: true),
            AppNotification(id: "seed-9", type: .icebreaker, title: "Conversation starter", body: "Try asking about their favorite Sindhi dish!", createdAt: Date().addingTimeInterval(-90000), isRead: true),
            AppNotification(id: "seed-10", type: .feature, title: "New feature: Voice Intros!", body: "Record a short voice intro to stand out from the crowd.", createdAt: Date().addingTimeInterval(-172800), isRead: true),
        ]
        saveNotifications()
    }
}

// MARK: - Notification Panel View

struct NotificationPanelView: View {
    @ObservedObject var notificationManager = NotificationManager.shared
    @Environment(\.dismiss) var dismiss
    @Environment(\.adaptiveColors) private var colors
    @Binding var selectedTab: Int

    init(selectedTab: Binding<Int> = .constant(0)) {
        _selectedTab = selectedTab
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.spacingMD) {
                    if notificationManager.notifications.isEmpty {
                        emptyState
                    } else {
                        notificationsList
                        clearAllButton
                    }

                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, AppTheme.spacingMD)
                .padding(.top, AppTheme.spacingSM)
            }
            .appBackground()
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 12) {
                        if notificationManager.unreadCount > 0 {
                            Button {
                                notificationManager.markAllRead()
                            } label: {
                                Text("Mark all read")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(AppTheme.rose)
                            }
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 16))
                                .foregroundColor(colors.textSecondary)
                        }

                        Button("Done") { dismiss() }
                            .foregroundColor(AppTheme.rose)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Notifications List

    @ViewBuilder
    private var notificationsList: some View {
        if !notificationManager.todayNotifications.isEmpty {
            sectionHeader("Today")
            ForEach(notificationManager.todayNotifications) { notification in
                NotificationRowView(
                    notification: notification,
                    onTap: { handleTap(notification) }
                )
            }
        }

        if !notificationManager.earlierNotifications.isEmpty {
            sectionHeader("Earlier")
            ForEach(notificationManager.earlierNotifications) { notification in
                NotificationRowView(
                    notification: notification,
                    onTap: { handleTap(notification) }
                )
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            icon: "bell.slash",
            title: "No notifications",
            message: "You're all caught up! New notifications will appear here."
        )
        .padding(.top, AppTheme.spacingXL)
    }

    // MARK: - Clear All Button

    private var clearAllButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.25)) {
                notificationManager.clearAll()
            }
        } label: {
            HStack {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                Text("Clear all notifications")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(colors.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(colors.textPrimary)
            .padding(.top, 8)
    }

    private func handleTap(_ notification: AppNotification) {
        notificationManager.handleNotificationTap(notification)
        if notification.type.destinationTab != nil {
            selectedTab = notificationManager.selectedTab
            dismiss()
        }
    }
}

// MARK: - Notification Row

struct NotificationRowView: View {
    let notification: AppNotification
    var onTap: () -> Void = {}
    @ObservedObject var notificationManager = NotificationManager.shared
    @Environment(\.adaptiveColors) private var colors
    @State private var offset: CGFloat = 0
    @State private var showDelete = false

    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete background
            if showDelete || offset < -20 {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.25)) {
                            notificationManager.dismiss(notification.id)
                        }
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60)
                    }
                    .frame(width: 60)
                    .background(AppTheme.error)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMD))
                }
            }

            // Main row
            HStack(alignment: .top, spacing: 12) {
                // Colored icon circle
                Image(systemName: notification.type.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(notification.type.color)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(notification.type.color.opacity(0.15))
                    )

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        Text(notification.title)
                            .font(.system(size: 14, weight: notification.isRead ? .medium : .semibold))
                            .foregroundColor(colors.textPrimary)

                        Spacer()

                        // Dismiss X button
                        Button {
                            withAnimation(.easeOut(duration: 0.25)) {
                                notificationManager.dismiss(notification.id)
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(colors.textMuted)
                                .frame(width: 20, height: 20)
                        }
                    }

                    Text(notification.body)
                        .font(.system(size: 13))
                        .foregroundColor(colors.textSecondary)
                        .lineLimit(2)

                    Text(notification.createdAt.timeAgoLong)
                        .font(.system(size: 11))
                        .foregroundColor(colors.textMuted)
                }

                // Unread dot
                if !notification.isRead {
                    Circle()
                        .fill(AppTheme.rose)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                    .fill(colors.cardDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                            .stroke(colors.border, lineWidth: 0.5)
                    )
                    .shadow(color: colors.cardShadowColor, radius: 4, x: 0, y: 2)
            )
            .offset(x: offset)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        if value.translation.width < 0 {
                            offset = value.translation.width
                        }
                    }
                    .onEnded { value in
                        if value.translation.width < -100 {
                            withAnimation(.easeOut(duration: 0.25)) {
                                notificationManager.dismiss(notification.id)
                            }
                        } else if value.translation.width < -50 {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                offset = -70
                                showDelete = true
                            }
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                offset = 0
                                showDelete = false
                            }
                        }
                    }
            )
            .onTapGesture {
                if showDelete {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        offset = 0
                        showDelete = false
                    }
                } else {
                    onTap()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMD))
    }
}
